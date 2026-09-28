#!/usr/bin/env bash
# Hand-run (`task orca:base-image`). Builds the project's dev image, layers the Orca infra on top,
# clones the repo, runs the sync command, and commits the result as the image `create` boots.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require_git_token
root="$(git -C "$here" rev-parse --show-toplevel)"

build="${image##*/}-build"  # container names reject the registry prefix
trap 'docker rm -f "$build" >/dev/null 2>&1 || true' EXIT

docker build -t "$image-dev" -f "$root/$dev_dockerfile" "$root" >&2
docker build -t "$image-infra" -f "$here/infra.Dockerfile" \
  --build-arg DEV_IMAGE="$image-dev" --build-arg GIT_HOST="$git_host" "$here" >&2
docker rm -f "$build" >/dev/null 2>&1 || true
# Entrypoint bypassed: sshd never runs here, so no host keys end up in the image.
docker run -i --name "$build" -u dev --entrypoint bash "$image-infra" -s <<<"$(sync_script)" >&2
docker commit \
  --change='ENTRYPOINT ["/usr/local/bin/orca-docker-ssh-entrypoint"]' --change='CMD []' --change='USER root' \
  "$build" "$image" >&2
