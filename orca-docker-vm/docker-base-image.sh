#!/usr/bin/env bash
# Hand-run (also run by prepare.sh). Builds the project's dev image, then layers the Orca infra, the
# repo checkout and its deps on top: the image every `create` boots. Needs no token: the checkout
# is a clone of the local repo, so only committed files reach the image and no secret enters a build.
# Installs only the agents set up by prepare.sh (those with a login volume).
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
root="$(git -C "$here" rev-parse --show-toplevel)"

# Build context: the files infra.Dockerfile copies, plus the clone under repo/. Not a named context
# (--build-context): that needs BuildKit, which Podman's Docker API lacks. Only the context root's
# .dockerignore applies, so the repo's own can't filter the checkout.
ctx="$(mktemp -d)"
trap 'rm -rf "$ctx"' EXIT
cp -p "$here/docker-entrypoint.sh" "$here/git-credential-orca" "$ctx"
git clone -q --branch "$repo_ref" "$root" "$ctx/repo" >&2

docker build -t "$image-dev" -f "$root/$dev_dockerfile" "$root" >&2
docker build -t "$image" -f "$here/infra.Dockerfile" \
  --build-arg DEV_IMAGE="$image-dev" --build-arg GIT_HOST="$git_host" --build-arg AGENTS="$(volume_agents)" \
  --build-arg REPO_URL="$repo_url" \
  --build-arg PROJECT_ROOT="$project_root" --build-arg SYNC_COMMAND="$sync_command" "$ctx" >&2
