#!/usr/bin/env bash
# Hand-run: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Claude token → git token → base image → end-to-end self-test (real create + destroy).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"

"$here/claude-token-setup.sh"
"$here/git-token-setup.sh"
"$here/docker-base-image.sh"
orca vm recipe doctor docker --repo-path "$root" --provision --json | jq -e '.ok' >/dev/null
echo "orca-docker-vm ready" >&2
