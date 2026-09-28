#!/usr/bin/env bash
# Hand-run once (and again when the token expires, ~1 year): issues a long-lived Claude token
# and stores it in the host keyring (see secret_store in lib.sh), shared by every project using this recipe.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ -z "${FORCE:-}" ] && [ -n "$(secret_get "$claude_token_keychain_service")" ]; then
  echo "Claude token already in $(secret_where "$claude_token_keychain_service"); FORCE=1 to reissue." >&2
  exit 0
fi

claude setup-token

echo
read -rsp "Paste the token printed above: " token
echo
[ -n "$token" ] || { echo "Empty token, nothing saved" >&2; exit 1; }

secret_set "$claude_token_keychain_service" "Orca: Claude Code token for Docker workspaces" \
  "Long-lived token from 'claude setup-token', shared by every project using orca-docker-vm. Written by orca-docker-vm/claude-token-setup.sh; read by orca-docker-vm/docker-create.sh and passed into each workspace container as CLAUDE_CODE_OAUTH_TOKEN." \
  "$token"
