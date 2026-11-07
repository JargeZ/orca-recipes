#!/usr/bin/env bash
# For the plugin's status bar: prints the first missing setup step of the repo at ORCA_REPO_PATH as
# one word. `ready` also prints the image's creation time and the last commit time of dev.Dockerfile,
# tab-separated, so the worker can see a stale image. Fast and quiet: no logins are checked (that
# needs a container), only that their volumes exist.
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh" 2>/dev/null  # config.sh exits without an origin remote
[ -f "$repo_root/$dev_dockerfile" ] || { echo no-dockerfile; exit 0; }
docker info >/dev/null 2>&1 || { echo no-docker; exit 0; }
created="$(docker image inspect -f '{{.Created}}' "$image" 2>/dev/null)" || { echo no-image; exit 0; }
[ -n "$(git_token)" ] || { echo no-token; exit 0; }
[ -n "$(volume_agents)" ] || { echo no-agents; exit 0; }
printf 'ready\t%s\t%s\n' "$created" "$(git -C "$repo_root" log -1 --format=%cI -- "$dev_dockerfile")"
