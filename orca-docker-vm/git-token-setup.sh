#!/usr/bin/env bash
# Hand-run once (and again when the token expires): stores a git token scoped to this repo only
# in the macOS Keychain, where the docker-*.sh scripts read it.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ -z "${FORCE:-}" ] && [ -n "$(keychain_value "$git_token_keychain_service")" ]; then
  echo "Git token already in Keychain as '$git_token_keychain_service'; FORCE=1 to replace." >&2
  exit 0
fi

repo="$(sed -E 's#^https://[^/]+/##; s#\.git$##' <<<"$repo_url")"
case "$git_host" in
  github.com) cat >&2 <<MSG
Create a fine-grained token:
  https://github.com/settings/personal-access-tokens/new?name=orca-${repo#*/}&target_name=${repo%%/*}&expires_in=90&contents=write&pull_requests=write&issues=write&workflows=write
Repository access: Only select repositories -> $repo
Permissions: Contents, Pull requests, Issues, Workflows = Read and write (Metadata read is implied).
MSG
  ;;
  *) cat >&2 <<MSG
Create a project access token (role Developer, scopes api + write_repository):
  https://$git_host/$repo/-/settings/access_tokens
MSG
  ;;
esac

read -rsp "Paste the token: " token
echo
[ -n "$token" ] || { echo "Empty token, nothing saved" >&2; exit 1; }
# Global config ignored: its credential helpers or insteadOf rewrites could mask a bad token.
# shellcheck disable=SC2016  # the helper expands the token itself
ORCA_GIT_TOKEN="$token" GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 git \
  -c credential.helper= -c 'credential.helper=!f() { printf "username=x-access-token\npassword=%s\n" "$ORCA_GIT_TOKEN"; }; f' \
  ls-remote --exit-code "$repo_url" HEAD >/dev/null
echo "Token can read $repo_url." >&2

# -l shows in the macOS access prompt; -D and -j in Keychain Access.
security add-generic-password -U -s "$git_token_keychain_service" -a "$USER" \
  -l "Orca: $project_slug git token for Docker workspaces" -D "Orca git token" \
  -j "Access token scoped to $repo_url only. Written by orca-docker-vm/git-token-setup.sh; read by orca-docker-vm/docker-create.sh and passed into each $project_slug workspace container as $git_token_env for git and the $git_host CLI." \
  -w "$token"
echo "Saved to Keychain as '$git_token_keychain_service'."
