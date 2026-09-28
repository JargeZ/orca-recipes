#!/usr/bin/env bash
# Hand-run (also step 3 of prepare.sh; FORCE=1 to log in again): signs Claude Code in once, inside a
# container, into the named volume every workspace mounts at CLAUDE_CONFIG_DIR - how Anthropic's dev
# container guide persists auth. Claude Code refreshes that login itself; nothing is stored on the host.
# Idempotent: checks the login with a real request and only asks you to log in when that fails.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

docker image inspect "$image" >/dev/null 2>&1 || { echo "No image $image: run orca-docker-vm/docker-base-image.sh" >&2; exit 1; }
docker volume create "$claude_volume" >/dev/null

check() {
  echo "Checking the Claude login in volume '$claude_volume' with a one-line request..." >&2
  local out
  if out="$(claude_run "$image" -p --model haiku 'Reply with just: ok' 2>&1)"; then
    echo "Claude login works: $(claude_run "$image" auth status --json | jq -r '"\(.email // "?") (\(.authMethod), \(.subscriptionType // "?"))"')." >&2
  else
    echo "Claude login doesn't work: ${out:-no output}" >&2
    return 1
  fi
}

if [ -z "${FORCE:-}" ] && check; then exit 0; fi

cat >&2 <<MSG

Logging in to Claude inside a container. Claude prints a URL: open it, approve, then paste the code
the browser shows back here (the browser can't reach the container, so it won't redirect).
MSG
claude_run -it "$image" auth login
check || { echo "Still not logged in; rerun orca-docker-vm/prepare.sh to try again." >&2; exit 1; }
