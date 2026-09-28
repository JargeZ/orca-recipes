#!/usr/bin/env bash
# Hand-run once (and again when the token expires, ~1 year): issues a long-lived Claude token
# and stores it in the macOS Keychain, shared by every project using this recipe.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

if [ -z "${FORCE:-}" ] && [ -n "$(keychain_value "$claude_token_keychain_service")" ]; then
  echo "Claude token already in Keychain as '$claude_token_keychain_service'; FORCE=1 to reissue." >&2
  exit 0
fi

claude setup-token

echo
read -rsp "Paste the token printed above: " token
echo
[ -n "$token" ] || { echo "Empty token, nothing saved" >&2; exit 1; }

security add-generic-password -U -s "$claude_token_keychain_service" -a "$USER" -w "$token"
echo "Saved to Keychain as '$claude_token_keychain_service'."
