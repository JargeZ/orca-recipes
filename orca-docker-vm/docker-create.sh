#!/usr/bin/env bash
# Orca `create`: boots a container from the base image, hands it the tokens, syncs the repo to
# repo_ref, reruns the sync command (the lock may have moved since the image), and prints the
# SSH recipe result.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

docker image inspect "$image" >/dev/null 2>&1 || { echo "No image $image: run orca-docker-vm/docker-base-image.sh" >&2; exit 1; }
CLAUDE_CODE_OAUTH_TOKEN="$(claude_token)"
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] || { echo "No Claude token: run orca-docker-vm/claude-token-setup.sh" >&2; exit 1; }
require_git_token

key="$here/.ssh/id_ed25519"
if [ ! -f "$key" ]; then
  mkdir -p "$here/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C orca-docker -f "$key"
fi

name="$(printf 'orca-%s-%s' "${ORCA_RECIPE_ID:-docker}" "${ORCA_VM_INSTANCE_ID:-$(date +%s)}" | tr -c 'a-zA-Z0-9_.-' '-' | cut -c1-60)"
ok=0
trap '[ "$ok" = 1 ] || { docker logs "$name" >&2 2>&1 || true; docker rm -f "$name" >/dev/null 2>&1 || true; }' EXIT

docker run -d --name "$name" -p 127.0.0.1::22 -e "ORCA_SSH_PUBLIC_KEY=$(cat "$key.pub")" "$image" >&2
port="$(docker port "$name" 22/tcp | head -1 | sed 's/.*://')"

host_key=""
for _ in $(seq 50); do
  host_key="$(docker exec "$name" cat /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null | cut -d' ' -f1,2)" && [ -n "$host_key" ] && break
  sleep 0.2
done
[ -n "$host_key" ] || { echo "container never generated an SSH host key" >&2; exit 1; }

# Host key read via trusted `docker exec`, so replacing a reused port's entry is safe.
known_hosts="$HOME/.ssh/known_hosts"
mkdir -p "$HOME/.ssh" && touch "$known_hosts"
ssh-keygen -R "[127.0.0.1]:$port" -f "$known_hosts" >/dev/null 2>&1 || true
echo "[127.0.0.1]:$port $host_key" >> "$known_hosts"

# Tokens live only in this container (never in the image): pam_env exports them to every SSH session.
docker exec -i "$name" sh -c 'cat >> /etc/environment' \
  <<<"$(printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n%s=%s\n' "$CLAUDE_CODE_OAUTH_TOKEN" "$git_token_env" "$(git_token)")"
for k in user.name user.email; do
  v="$(git config --global "$k" || true)"
  [ -z "$v" ] || docker exec -u dev "$name" git config --global "$k" "$v"
done

docker exec -i -u dev "$name" bash -s <<<"$(sync_script)" >&2

# Checks what an Orca session actually gets: SSH login env, Claude auth, git auth.
ssh_opts=(-i "$key" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes)
for _ in $(seq 50); do
  ssh "${ssh_opts[@]}" dev@127.0.0.1 true 2>/dev/null && break
  sleep 0.2
done
# shellcheck disable=SC2029  # project_root expands locally on purpose
ssh "${ssh_opts[@]}" dev@127.0.0.1 \
  "claude --version && test -n \"\$CLAUDE_CODE_OAUTH_TOKEN\" && cd '$project_root' && git ls-remote --exit-code origin HEAD >/dev/null" >&2

jq -n --arg name "$name" --argjson port "$port" --arg key "$key" --arg root "$project_root" --arg hk "$host_key" '{
  schemaVersion: 1,
  connection: {
    type: "ssh",
    projectRoot: $root,
    target: { label: $name, host: "127.0.0.1", port: $port, username: "dev", identityFile: $key, identitiesOnly: true }
  },
  userData: { provider: "docker", resourceId: $name, hostKey: $hk }
}'
ok=1
