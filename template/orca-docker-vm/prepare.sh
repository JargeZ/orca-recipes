#!/usr/bin/env bash
# Hand-run: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Asks which agents to set up, then: git token → base image → each chosen agent's login → end-to-end
# self-test (real create + destroy). Every step checks first and only asks for input when something is
# missing or broken, so rerunning it is how you fix things.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
root="$(git -C "$here" rev-parse --show-toplevel)"

n=0
trap 'echo "prepare.sh: failed at step $n, see the output above" >&2' ERR

# Orca matches a workspace's checkout (origin = repo_url) to the project by owner/repo; a mismatch
# with the local origin fails with "Imported folder does not match the selected project identity".
# Host is ignored so SSH aliases (git@github-work:...) still match.
repo_path() { sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@/]+@[^:]+:##; s#\.git$##; s#/+$##' <<<"$1" | tr '[:upper:]' '[:lower:]'; }
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ] && [ "$(repo_path "$origin")" != "$(repo_path "$repo_url")" ]; then
  echo "repo_url ($repo_url) and the local origin ($origin) are different repos; Orca won't match" \
    "workspaces to this project. Fix repo_url with orca-docker-vm/update.sh or the origin remote." >&2
  false
fi

# Asked up front so the long steps run unattended. Without a terminal every agent is set up.
chosen=()
for a in "${agents[@]}"; do
  label="$(agent_var "$a" label)" volume="$(agent_var "$a" volume)"
  ans=y
  [ ! -t 0 ] || read -r -p "Set up $label in workspaces? [Y/n] " ans
  case "$ans" in
    [nN]*) ! docker volume inspect "$volume" >/dev/null 2>&1 \
      || echo "  Volume '$volume' already exists, so workspaces still use $label; \`docker volume rm $volume\` drops it." >&2 ;;
    *) chosen+=("$a") ;;
  esac
done

total=$((3 + ${#chosen[@]}))
step() { n=$((n + 1)); printf '\n==> [%s/%s] %s\n' "$n" "$total" "$1" >&2; }

step "Git token (keyring)"
"$here/git-token-setup.sh"

step "Base image (docker build)"
"$here/docker-base-image.sh"
echo "Image built." >&2

for a in ${chosen[@]+"${chosen[@]}"}; do
  step "$(agent_var "$a" label) login (shared Docker volume)"
  "$here/$a-login.sh"
done

step "orca vm recipe doctor: real create + destroy of a workspace (takes a minute)"
report="$(orca vm recipe doctor docker --repo-path "$root" --provision --json || true)"
if ! jq -e '.ok' >/dev/null 2>&1 <<<"$report"; then
  echo "Doctor reported a problem:" >&2
  jq . <<<"$report" >&2 2>/dev/null || echo "$report" >&2
  false
fi
echo "Doctor: ok." >&2

printf '\nAll set: Orca can now create "Local Docker" workspaces for this repo.\n' >&2
