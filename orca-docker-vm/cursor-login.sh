#!/usr/bin/env bash
# Hand-run (also a step of prepare.sh; FORCE=1 to log in again): signs Cursor Agent in once, inside a
# container, into the named volume every workspace mounts at CURSOR_CONFIG_DIR. Uses the file
# credential store (AGENT_CLI_CREDENTIAL_STORE=file); nothing is taken from the host Cursor login.
# Idempotent: checks auth status and only asks you to log in when that fails.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

docker image inspect "$image" >/dev/null 2>&1 || { echo "No image $image: run orca-docker-vm/docker-base-image.sh" >&2; exit 1; }
docker volume create "$cursor_volume" >/dev/null

check() {
  echo "Checking the Cursor Agent login in volume '$cursor_volume'..." >&2
  local out
  if out="$(cursor_run "$image" status --format json 2>&1)" \
    && jq -e '.isAuthenticated == true' >/dev/null 2>&1 <<<"$out"; then
    echo "Cursor Agent login works: $(jq -r '.userInfo.email // .email // "?"' <<<"$out")." >&2
  else
    echo "Cursor Agent login doesn't work: ${out:-no output}" >&2
    return 1
  fi
}

if [ -z "${FORCE:-}" ] && check; then exit 0; fi

cat >&2 <<MSG

Logging in to Cursor Agent inside a container. Agent prints a URL: open it and approve (the browser
can't reach the container, so set NO_OPEN_BROWSER and paste/approve from the printed link).
MSG
cursor_run -it -e NO_OPEN_BROWSER=1 "$image" login
check || { echo "Still not logged in; rerun orca-docker-vm/prepare.sh to try again." >&2; exit 1; }
