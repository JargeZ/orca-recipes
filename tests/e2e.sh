#!/usr/bin/env bash
# Slow, needs Docker + network: renders against a real repo, builds the image, creates a workspace
# container, checks what an Orca SSH session gets, then destroys it.
# Env: E2E_REPO_URL, E2E_REPO_REF, E2E_SYNC (defaults target a uv project);
#      ORCA_GIT_TOKEN (default: `gh auth token`, test-only) and CLAUDE_CODE_OAUTH_TOKEN
#      (default: Keychain entry E2E_CLAUDE_KEYCHAIN, default orca-claude-token).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
repo_url="${E2E_REPO_URL:-https://github.com/JargeZ/django-orm-markdown-backend.git}"
export ORCA_GIT_TOKEN="${ORCA_GIT_TOKEN:-$(gh auth token)}"
export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-$(security find-generic-password -s "${E2E_CLAUDE_KEYCHAIN:-orca-claude-token}" -w)}"

result=""
cleanup() {
  [ -z "$result" ] || "$tmp/p/scripts/orca-vm/docker-destroy.sh" <<<"{\"recipeResult\": $result}" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

render "$tmp/p" -d "repo_url=$repo_url" -d "repo_ref=${E2E_REPO_REF:-master}" \
  -d project_slug=orca-recipes-e2e -d "sync_command=${E2E_SYNC:-uv sync}"
s="$tmp/p/scripts/orca-vm"

"$s/docker-base-image.sh"
result="$(ORCA_VM_INSTANCE_ID="e2e-$$" "$s/docker-create.sh")"
name="$(jq -er .userData.resourceId <<<"$result")"
port="$(jq -er .connection.target.port <<<"$result")"
root="$(jq -er .connection.projectRoot <<<"$result")"

on() { ssh -i "$s/.ssh/id_ed25519" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes dev@127.0.0.1 "$@"; }
on 'gh auth status' >/dev/null 2>&1 || fail "gh not authenticated in SSH session"
on "cd $root && git push --dry-run origin HEAD:refs/heads/orca-e2e-probe" >/dev/null 2>&1 || fail "git push not authorized"
[ "$(on 'echo $VIRTUAL_ENV')" = /opt/venv ] || fail "dev.Dockerfile ENV not in SSH session"
[ "$(on 'bash -lc "echo \$VIRTUAL_ENV"')" = /opt/venv ] || fail "dev.Dockerfile ENV not in login shell"
[ "$(on 'git config user.email')" = "$(git config --global user.email)" ] || fail "git identity not copied"
on "cd $root && uv run python -c 'import django'" || fail "synced deps not importable"
on 'env' | grep -q "^GH_TOKEN=" || fail "token not in session env"
docker image inspect localhost/orca-recipes-e2e-orca --format '{{json .Config.Env}}' | grep -q TOKEN && fail "token baked into image"

"$s/docker-destroy.sh" <<<"{\"recipeResult\": $result}"; result=""
docker inspect "$name" >/dev/null 2>&1 && fail "container survived destroy"
echo "e2e: ok"
