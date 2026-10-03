#!/usr/bin/env bash
# Hand-run: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Git token → base image → Claude login → Cursor login → end-to-end self-test (real create + destroy).
# Every step checks first and only asks for input when something is missing or broken, so rerunning
# it is how you fix things.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"

step() { printf '\n==> [%s/5] %s\n' "$1" "$2" >&2; }
trap 'echo "prepare.sh: failed at step $n, see the output above" >&2' ERR

# Orca matches a workspace's checkout (origin = repo_url) to the project by owner/repo; a mismatch
# with the local origin fails with "Imported folder does not match the selected project identity".
# Host is ignored so SSH aliases (git@github-work:...) still match.
n=0
repo_path() { sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@/]+@[^:]+:##; s#\.git$##; s#/+$##' <<<"$1" | tr '[:upper:]' '[:lower:]'; }
# shellcheck source=config.sh
repo_url="$(source "$here/config.sh" && echo "$repo_url")"
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ] && [ "$(repo_path "$origin")" != "$(repo_path "$repo_url")" ]; then
  echo "repo_url ($repo_url) and the local origin ($origin) are different repos; Orca won't match" \
    "workspaces to this project. Fix repo_url with orca-docker-vm/update.sh or the origin remote." >&2
  false
fi

n=1; step $n "Git token (keyring)"
"$here/git-token-setup.sh"

n=2; step $n "Base image (docker build)"
"$here/docker-base-image.sh"
echo "Image built." >&2

n=3; step $n "Claude login (shared Docker volume)"
"$here/claude-login.sh"

n=4; step $n "Cursor Agent login (shared Docker volume)"
"$here/cursor-login.sh"

n=5; step $n "orca vm recipe doctor: real create + destroy of a workspace (takes a minute)"
report="$(orca vm recipe doctor docker --repo-path "$root" --provision --json || true)"
if ! jq -e '.ok' >/dev/null 2>&1 <<<"$report"; then
  echo "Doctor reported a problem:" >&2
  jq . <<<"$report" >&2 2>/dev/null || echo "$report" >&2
  false
fi
echo "Doctor: ok." >&2

printf '\nAll set: Orca can now create "Local Docker" workspaces for this repo.\n' >&2
