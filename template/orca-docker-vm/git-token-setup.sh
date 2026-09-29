#!/usr/bin/env bash
# Hand-run once (and again when the token expires): stores a git token scoped to this repo only
# in the host keyring (see secret_store in lib.sh), where the docker-*.sh scripts read it.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ -z "${FORCE:-}" ] && [ -n "$(secret_get "$git_token_keychain_service")" ]; then
  echo "Git token already in $(secret_where "$git_token_keychain_service"); FORCE=1 to replace." >&2
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
  # Neither GitLab form takes prefill query params (unlike the legacy PAT form), so print the values.
  *) cat >&2 <<MSG
Create one token limited to $repo. Either kind works, fill in:
  Name:        orca-${repo##*/}
  Description: Orca Docker workspaces for $repo
  Expiration:  90 days

A) Project access token (gitlab.com: Premium/Ultimate only; self-managed: any tier):
  https://$git_host/$repo/-/settings/access_tokens
  Role: Developer. Scopes: api, write_repository.

B) Fine-grained personal access token (any tier; GitLab 18.10+):
  https://$git_host/-/user_settings/personal_access_tokens/granular/new
  Group and project access: only the project $repo.
  Permissions: Code = Download + Push; for glab also Merge request, Issue, Pipeline = read + write.
MSG
  ;;
esac

read -rsp "Paste the token: " token
echo
[ -n "$token" ] || { echo "Empty token, nothing saved" >&2; exit 1; }
# A dry-run push authenticates even on a public or empty repo (ls-remote does neither) and needs
# write access. Global config ignored: its credential helpers or insteadOf rewrites could mask a bad token.
# shellcheck disable=SC2016  # the helper expands the token itself
if ! ORCA_GIT_TOKEN="$token" GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 git -C "$here" \
  -c credential.helper= -c 'credential.helper=!f() { printf "username=x-access-token\npassword=%s\n" "$ORCA_GIT_TOKEN"; }; f' \
  push -q --dry-run "$repo_url" HEAD:refs/heads/orca-token-check >/dev/null; then
  echo "Token can't push to $repo_url (see git's error above), nothing saved" >&2
  exit 1
fi
echo "Token can write to $repo_url." >&2

secret_set "$git_token_keychain_service" "Orca: $project_slug git token for Docker workspaces" \
  "Access token scoped to $repo_url only. Written by orca-docker-vm/git-token-setup.sh; read by orca-docker-vm/docker-create.sh and passed into each $project_slug workspace container as $git_token_env for git and the $git_host CLI." \
  "$token"
