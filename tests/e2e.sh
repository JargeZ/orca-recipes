#!/usr/bin/env bash
# Slow, needs Docker + network: runs this repo's own recipe (`task render` first) for real - builds
# the image, creates a workspace container, checks what an Orca SSH session gets, then destroys it.
# create fetches repo_ref from GitHub, so the branch must be pushed.
# Env: ORCA_GIT_TOKEN (default: `gh auth token`, test-only) and CLAUDE_CODE_OAUTH_TOKEN
#      (default: Keychain entry E2E_CLAUDE_KEYCHAIN, default orca-claude-token).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export ORCA_GIT_TOKEN="${ORCA_GIT_TOKEN:-$(gh auth token)}"
export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-$(security find-generic-password -s "${E2E_CLAUDE_KEYCHAIN:-orca-claude-token}" -w)}"
s="$root/orca-docker-vm"
source "$s/config.sh"

result=""
cleanup() {
  [ -z "$result" ] || "$s/docker-destroy.sh" <<<"{\"recipeResult\": $result}" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

"$s/docker-base-image.sh"
for t in "$ORCA_GIT_TOKEN" "$CLAUDE_CODE_OAUTH_TOKEN"; do
  { docker image inspect "$image"; docker history --no-trunc "$image"; } | grep -qF "$t" && fail "token baked into image"
done
result="$(ORCA_VM_INSTANCE_ID="e2e-$$" "$s/docker-create.sh")"
name="$(jq -er .userData.resourceId <<<"$result")"
port="$(jq -er .connection.target.port <<<"$result")"

on() { ssh -i "$s/.ssh/id_ed25519" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes dev@127.0.0.1 "$@"; }
on 'gh auth status' >/dev/null 2>&1 || fail "gh not authenticated in SSH session"
on "cd $project_root && git push --dry-run origin HEAD:refs/heads/orca-e2e-probe" >/dev/null 2>&1 || fail "git push not authorized"
[ "$(on 'echo $UV_PYTHON_DOWNLOADS')" = never ] || fail "dev.Dockerfile ENV not in SSH session"
[ "$(on 'bash -lc "echo \$UV_PYTHON_DOWNLOADS"')" = never ] || fail "dev.Dockerfile ENV not in login shell"
[ "$(on 'git config user.email')" = "$(git config --global user.email)" ] || fail "git identity not copied"
on "cd $project_root && uvx --offline copier --version" >/dev/null || fail "synced deps not cached"
on 'env' | grep -q "^$git_token_env=" || fail "token not in session env"

"$s/docker-destroy.sh" <<<"{\"recipeResult\": $result}"; result=""
docker inspect "$name" >/dev/null 2>&1 && fail "container survived destroy"
echo "e2e: ok"
