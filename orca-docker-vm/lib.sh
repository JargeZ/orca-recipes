# shellcheck shell=bash
# Sourced by the recipe scripts. stdout is reserved for each script's final JSON.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$here/config.sh"

keychain_value() { security find-generic-password -s "$1" -w 2>/dev/null || true; }

claude_token() { printf '%s' "${CLAUDE_CODE_OAUTH_TOKEN:-$(keychain_value "$claude_token_keychain_service")}"; }

# Token scoped to this repo only; never the host's broad `gh auth token`.
git_token() { printf '%s' "${ORCA_GIT_TOKEN:-$(keychain_value "$git_token_keychain_service")}"; }

require_git_token() {
  token="$(git_token)"
  [ -n "$token" ] || { echo "No git token: run orca-docker-vm/git-token-setup.sh (or set ORCA_GIT_TOKEN)" >&2; exit 1; }
  export "$git_token_env=$token"
}

# Script for `docker exec bash -s` inside a workspace container as `dev`: fetches repo_ref through the
# image's credential helper, then reruns the project's sync command. The token travels over stdin,
# so it stays out of `docker inspect`.
sync_script() {
  local v
  for v in "$git_token_env" repo_url repo_ref project_root sync_command; do printf 'export %s=%q\n' "$v" "${!v}"; done
  printf '%s' "$remote_sync_script"
}

# shellcheck disable=SC2016
remote_sync_script='set -euo pipefail
export GIT_TERMINAL_PROMPT=0
cd "$project_root"
git fetch origin "$repo_ref"
git checkout -B "$repo_ref" FETCH_HEAD
bash -lc "$sync_command"
'
