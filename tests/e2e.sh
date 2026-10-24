#!/usr/bin/env bash
# Slow, needs Docker + network: runs this repo's own recipe (`task render` first) for real - builds
# the image, creates a workspace container, checks what an Orca SSH session gets, then destroys it.
# create fetches repo_ref from GitHub, so the branch must be pushed.
# Needs every agent's login volume set up (prepare.sh, or each .orca-vm/<agent>-login.sh), and the
# orca CLI (prepare.sh --yes runs the doctor).
# Env: ORCA_GIT_TOKEN (default: `gh auth token`, test-only).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export ORCA_GIT_TOKEN="${ORCA_GIT_TOKEN:-$(gh auth token)}"
s="$root/.orca-vm"
source "$s/lib.sh"

result=""
u="" uid="e2e-$$"
cleanup() {
  [ -z "$result" ] || "$s/docker-destroy.sh" <<<"{\"recipeResult\": $result}" >/dev/null 2>&1 || true
  if [ -n "$u" ]; then
    rm -rf "$u"
    docker volume rm "orca-$uid-claude" "orca-$uid-cursor" "orca-$uid-opencode" >/dev/null 2>&1 || true
    docker image rm "localhost/orca-recipes-$uid-orca" "localhost/orca-recipes-$uid-orca-dev" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

"$s/docker-base-image.sh"
{ docker image inspect "$image"; docker history --no-trunc "$image"; } | grep -qF "$ORCA_GIT_TOKEN" && fail "token baked into image"
result="$(ORCA_VM_INSTANCE_ID="e2e-$$" "$s/docker-create.sh")"
name="$(jq -er .userData.resourceId <<<"$result")"
port="$(jq -er .connection.target.port <<<"$result")"

on() { ssh -i "$s/.ssh/id_ed25519" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes dev@127.0.0.1 "$@"; }
on 'gh auth status' >/dev/null 2>&1 || fail "gh not authenticated in SSH session"
on 'claude -p --model haiku "Reply with just: ok"' >/dev/null 2>&1 || fail "claude not logged in in SSH session"
for a in "${agents[@]}"; do
  on "$(agent_var "$a" check)" >/dev/null 2>&1 || fail "$a not logged in in SSH session"
done
on "cd $project_root && git push --dry-run origin HEAD:refs/heads/orca-e2e-probe" >/dev/null 2>&1 || fail "git push not authorized"
[ "$(on 'echo $UV_PYTHON_DOWNLOADS')" = never ] || fail "dev.Dockerfile ENV not in SSH session"
[ "$(on 'bash -lc "echo \$UV_PYTHON_DOWNLOADS"')" = never ] || fail "dev.Dockerfile ENV not in login shell"
[ "$(on 'git config user.email')" = "$(git config --global user.email)" ] || fail "git identity not copied"
on "cd $project_root && uvx --offline copier --version" >/dev/null || fail "synced deps not cached"
on 'env' | grep -q "^$git_token_env=" || fail "token not in session env"
volume=""
if [ "$podman" = true ]; then
  on 'docker run --rm docker.io/library/hello-world' >/dev/null 2>&1 || fail "docker run inside workspace"
  on 'd=$(mktemp -d) && printf "FROM docker.io/library/alpine\nRUN true\n" > $d/Dockerfile && docker build -q $d' >/dev/null 2>&1 \
    || fail "docker build inside workspace"
  on 'docker compose version' >/dev/null 2>&1 || fail "docker compose missing"
  volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/home/dev/.local/share/containers"}}{{.Name}}{{end}}{{end}}' "$name")"
fi

"$s/docker-destroy.sh" <<<"{\"recipeResult\": $result}"; result=""
docker inspect "$name" >/dev/null 2>&1 && fail "container survived destroy"
[ -n "$volume" ] && docker volume inspect "$volume" >/dev/null 2>&1 && fail "podman storage volume survived destroy"
# Unattended prepare.sh (meta), on a copy of the recipe with its own image and cursor/opencode
# volumes, so the real ones stay as they are. The copy is in the repo: prepare.sh needs the checkout.
u="$(mktemp -d "$root/.orca-vm-$uid.XXXX")"
cp -R "$s/." "$u"
sed -i.bak -e "s/^project_slug=.*/project_slug='orca-recipes-$uid'/" \
  -e "s/^cursor_volume=.*/cursor_volume='orca-$uid-cursor'/" -e "s/^opencode_volume=.*/opencode_volume='orca-$uid-opencode'/" "$u/config.sh"
"$u/prepare.sh" --yes --agents claude </dev/null >/dev/null 2>"$tmp/err" \
  || { cat "$tmp/err" >&2; fail "prepare.sh --yes --agents claude with a Claude login"; }
for a in cursor opencode; do
  docker volume inspect "orca-$uid-$a" >/dev/null 2>&1 && fail "prepare.sh --agents claude created the $a volume"
done
# Same with an empty Claude volume: fails fast with what to run, instead of waiting at a login prompt.
sed -i.bak "s/^claude_volume=.*/claude_volume='orca-$uid-claude'/" "$u/config.sh"
start=$SECONDS
"$u/prepare.sh" --yes --agents claude </dev/null >/dev/null 2>"$tmp/err" && fail "prepare.sh --yes passed without a Claude login"
[ $((SECONDS - start)) -lt 60 ] || fail "prepare.sh --yes without a Claude login took $((SECONDS - start))s"
tail -n1 "$tmp/err" | grep -q claude-login.sh || fail "last stderr line has no claude-login.sh: $(tail -n1 "$tmp/err")"

echo "e2e: ok"
