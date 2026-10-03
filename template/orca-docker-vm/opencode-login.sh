#!/usr/bin/env bash
# Hand-run (also a step of prepare.sh; FORCE=1 to log in again): signs OpenCode v2 in once, inside a
# container, into the named volume every workspace mounts at OpenCode's data dir. v2 keeps credentials
# in its SQLite db there (not auth.json); nothing is taken from the host OpenCode login.
# Idempotent: checks for a saved integration and only asks you to log in when there is none.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

docker image inspect "$image" >/dev/null 2>&1 || { echo "No image $image: run orca-docker-vm/docker-base-image.sh" >&2; exit 1; }
docker volume create "$opencode_volume" >/dev/null

# --standalone: a private in-process server that exits with the command, instead of the background
# service the container would kill mid-write.
check() {
  echo "Checking the OpenCode login in volume '$opencode_volume'..." >&2
  local out
  if out="$(opencode_run "$image" auth list --standalone --format json 2>&1)" \
    && jq -e 'length > 0' >/dev/null 2>&1 <<<"$out"; then
    echo "OpenCode login works: $(jq length <<<"$out") saved integration(s)." >&2
  else
    echo "OpenCode login doesn't work: ${out:-no output}" >&2
    return 1
  fi
}

if [ -z "${FORCE:-}" ] && check; then exit 0; fi

cat >&2 <<MSG

Logging in to OpenCode inside a container. Pick a provider; for OAuth it prints a URL or device code:
open it in your browser and approve (the browser can't reach the container, so paste back any code).
MSG
opencode_run -it "$image" auth login --standalone
check || { echo "Still not logged in; rerun orca-docker-vm/prepare.sh to try again." >&2; exit 1; }
