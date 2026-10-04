#!/usr/bin/env bash
# Orca `create`: boots a container from the base image with the shared login volumes of the agents
# prepare.sh set up, hands it the git token, checks out the workspace branch, reruns the sync command
# (the lock may have moved since the image), and prints the SSH recipe result.
# With `checkoutMode: provisioned-root` in orca.yaml (schema 2) that checkout is the workspace itself:
# one container per workspace, one entry in Orca. Schema 1 (older orca.yaml) keeps Orca's default of
# a linked worktree next to a repo_ref checkout.
# Known Orca gaps for these workspaces:
#   Source Control and Agent Session History panels stay empty: https://github.com/stablyai/orca/issues/22229
#   recipe SSH targets lose SSH-host features (session history, Open in VS Code, drag & drop; likely
#   also the Ports tab, no dedicated issue): https://github.com/stablyai/orca/issues/10946
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

docker image inspect "$image" >/dev/null 2>&1 || { echo "No image $image: run orca-docker-vm/docker-base-image.sh" >&2; exit 1; }
# Agents set up by prepare.sh = those whose login volume exists. Checked first: `docker run -v` would
# silently create an empty, logged-out volume.
enabled=() mounts=()
for a in "${agents[@]}"; do
  if docker volume inspect "$(agent_var "$a" volume)" >/dev/null 2>&1; then
    enabled+=("$a"); mounts+=(-v "$(agent_var "$a" mount)")
  else
    echo "$(agent_var "$a" label) is not set up (no volume '$(agent_var "$a" volume)'), skipping it; orca-docker-vm/prepare.sh adds it." >&2
  fi
done
require_git_token
schema="${ORCA_RECIPE_RESULT_SCHEMA_VERSION:-1}"
case "$schema" in 1|2) ;; *) echo "Unsupported ORCA_RECIPE_RESULT_SCHEMA_VERSION=$schema" >&2; exit 1 ;; esac
[ "$schema" = 2 ] || unset ORCA_REPO_REF_HEAD ORCA_REPO_BRANCH

key="$here/.ssh/id_ed25519"
if [ ! -f "$key" ]; then
  mkdir -p "$here/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C orca-docker -f "$key"
fi

name="$(printf 'orca-%s-%s' "${ORCA_RECIPE_ID:-docker}" "${ORCA_VM_INSTANCE_ID:-$(date +%s)}" | tr -c 'a-zA-Z0-9_.-' '-' | cut -c1-60)"
ok=0
trap '[ "$ok" = 1 ] || { docker logs "$name" >&2 2>&1 || true; docker rm -fv "$name" >/dev/null 2>&1 || true; }' EXIT

run_opts=()
# Podman (copier `podman`), rootless inside without --privileged: its user namespaces need seccomp and
# AppArmor off and an unmasked /proc, slirp4netns needs /dev/net/tun; storage is an anonymous volume,
# removed by `docker rm -v` in docker-destroy.sh. --init reaps the background service.
[ "$podman" != true ] || run_opts+=(--init --device /dev/net/tun -v /home/dev/.local/share/containers
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined)
docker run -d --name "$name" -p 127.0.0.1::22 ${run_opts[@]+"${run_opts[@]}"} ${mounts[@]+"${mounts[@]}"} \
  -e "ORCA_SSH_PUBLIC_KEY=$(cat "$key.pub")" "$image" >&2
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

# The git token lives only in this container (never in the image): pam_env exports it to every SSH session.
# glab defaults to gitlab.com; GITLAB_HOST points it at the repo's host.
env_lines="$git_token_env=$(git_token)"
[ "$git_token_env" != GITLAB_TOKEN ] || env_lines+=$'\n'"GITLAB_HOST=https://$git_host"
docker exec -i "$name" sh -c 'cat >> /etc/environment' <<<"$env_lines"
for k in user.name user.email; do
  v="$(git config --global "$k" || true)"
  [ -z "$v" ] || docker exec -u dev "$name" git config --global "$k" "$v"
done

docker exec -i -u dev "$name" bash -s <<<"$(sync_script)" >&2 \
  || { echo "Checking out ${ORCA_REPO_BRANCH:-$repo_ref} from $repo_url failed: is it pushed there?" >&2; exit 1; }

# Checks what an Orca session actually gets: SSH login env, each agent's auth, git auth.
ssh_opts=(-i "$key" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes)
for _ in $(seq 50); do
  ssh "${ssh_opts[@]}" dev@127.0.0.1 true 2>/dev/null && break
  sleep 0.2
done
for a in ${enabled[@]+"${enabled[@]}"}; do
  # shellcheck disable=SC2029  # the check runs remotely, as written in lib.sh
  ssh "${ssh_opts[@]}" dev@127.0.0.1 "$(agent_var "$a" check)" >&2 \
    || { echo "$(agent_var "$a" label) is not logged in (volume '$(agent_var "$a" volume)'): run orca-docker-vm/prepare.sh" >&2; exit 1; }
done
if [ "$podman" = true ]; then
  for i in $(seq 50); do
    ssh "${ssh_opts[@]}" dev@127.0.0.1 'docker info >/dev/null 2>&1' && break
    [ "$i" != 50 ] || { docker exec "$name" tail -5 /var/log/podman.log >&2; echo "Docker API (rootless Podman) did not come up" >&2; exit 1; }
    sleep 0.2
  done
fi
# shellcheck disable=SC2029  # project_root expands locally on purpose
ssh "${ssh_opts[@]}" dev@127.0.0.1 "cd '$project_root' && git ls-remote --exit-code origin HEAD >/dev/null" >&2

jq -n --argjson schema "$schema" --arg name "$name" --argjson port "$port" --arg key "$key" --arg root "$project_root" --arg hk "$host_key" '{
  schemaVersion: $schema,
  checkoutMode: "provisioned-root",
  connection: {
    type: "ssh",
    projectRoot: $root,
    target: { label: $name, host: "127.0.0.1", port: $port, username: "dev", identityFile: $key, identitiesOnly: true }
  },
  userData: { provider: "docker", resourceId: $name, hostKey: $hk }
} | if $schema == 1 then del(.checkoutMode) else . end'
ok=1
