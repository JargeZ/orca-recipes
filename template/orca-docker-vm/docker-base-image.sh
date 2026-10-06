#!/usr/bin/env bash
# Hand-run (also run by prepare.sh). Builds the project's dev image, then layers the Orca infra, the
# repo checkout and its deps on top: the image every `create` boots. Needs no token: the checkout
# is a clone of the local repo, so only committed files reach the image and no secret enters a build.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
root="$(git -C "$here" rev-parse --show-toplevel)"

src="$(mktemp -d)"
trap 'rm -rf "$src"' EXIT
git clone -q --branch "$repo_ref" "$root" "$src" >&2
# BuildKit applies a context's .dockerignore to named contexts too; one excluding .git would break
# the checkout. infra.Dockerfile restores the file from git.
rm -f "$src/.dockerignore"

docker build -t "$image-dev" -f "$root/$dev_dockerfile" "$root" >&2
docker build -t "$image" -f "$here/infra.Dockerfile" --build-context repo="$src" \
  --build-arg DEV_IMAGE="$image-dev" --build-arg GIT_HOST="$git_host" --build-arg REPO_URL="$repo_url" \
  --build-arg PROJECT_ROOT="$project_root" --build-arg SYNC_COMMAND="$sync_command" "$here" >&2
