#!/usr/bin/env bash
# Hand-run: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Claude token → git token → base image → end-to-end self-test (real create + destroy).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"

step() { printf '\n==> [%s/4] %s\n' "$1" "$2" >&2; }
trap 'echo "prepare.sh: failed at step $n, see the output above" >&2' ERR

n=1; step $n "Claude token (Keychain)"
"$here/claude-token-setup.sh"

n=2; step $n "Git token (Keychain)"
"$here/git-token-setup.sh"

n=3; step $n "Base image (docker build)"
"$here/docker-base-image.sh"
echo "Image built." >&2

n=4; step $n "orca vm recipe doctor: real create + destroy of a workspace (takes a minute)"
report="$(orca vm recipe doctor docker --repo-path "$root" --provision --json || true)"
if ! jq -e '.ok' >/dev/null 2>&1 <<<"$report"; then
  echo "Doctor reported a problem:" >&2
  jq . <<<"$report" >&2 2>/dev/null || echo "$report" >&2
  false
fi
echo "Doctor: ok." >&2

printf '\nAll set: Orca can now create "Local Docker" workspaces for this repo.\n' >&2
