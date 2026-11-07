#!/usr/bin/env bash
# Runs the plugin recipe (plugin/recipes/docker.json) the way Orca does: `sh -c <command>` in the repo
# root with Orca's ORCA_* variables, the lifecycle payload on stdin and the JSON on stdout. Needs the
# image and logins first: bash plugin/vm/prepare.sh. Git token: ORCA_GIT_TOKEN, default `gh auth token`
# (the test container is thrown away). The scripts unpack to a temporary cache dir.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
recipe="$repo/plugin/recipes/docker.json"
export ORCA_GIT_TOKEN="${ORCA_GIT_TOKEN:-$(gh auth token)}"
XDG_CACHE_HOME="$(mktemp -d)"
export XDG_CACHE_HOME ORCA_RECIPE_ID=docker ORCA_REPO_PATH="$repo" ORCA_RECIPE_RESULT_SCHEMA_VERSION=2
trap 'rm -rf "$XDG_CACHE_HOME"' EXIT

python3 "$repo/plugin/build.py" --check
cd "$repo"
echo "==> create" >&2
result="$(ORCA_VM_MODE=create ORCA_VM_INSTANCE_ID="plugin-e2e-$(date +%s)" sh -c "$(jq -r .create "$recipe")" </dev/null)"
name="$(jq -re .userData.resourceId <<<"$result")"
port="$(jq -re .connection.target.port <<<"$result")"
key="$(jq -re .connection.target.identityFile <<<"$result")"
jq -e '.checkoutMode == "provisioned-root"' <<<"$result" >/dev/null

echo "==> SSH into $name" >&2
ssh -i "$key" -p "$port" -o BatchMode=yes -o IdentitiesOnly=yes dev@127.0.0.1 \
  'cd "$HOME"/orca-recipes && git status --short --branch && docker info --format "docker: {{.ServerVersion}}"' >&2

echo "==> destroy" >&2
jq '{recipeResult: .}' <<<"$result" | ORCA_VM_MODE=destroy sh -c "$(jq -r .destroy "$recipe")" >&2
! docker inspect "$name" >/dev/null 2>&1 || { echo "container $name is still there" >&2; exit 1; }
echo "plugin e2e: ok" >&2
