#!/usr/bin/env bash
# Palette "Local Docker: prepare" runs it: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Asks which agents to set up, then: git token → base image → each chosen agent's login → end-to-end
# self-test (real create + destroy). Every step checks first and only asks for input when something is
# missing or broken, so rerunning it is how you fix things.
# Unattended (meta): prepare.sh --yes --agents claude. See parse_yes in lib.sh.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
  echo "Usage: $0 [--yes] [--agents <id>[,<id>...]]   agents: ${agents[*]}" >&2
  echo "  --yes     no questions; steps that need a person only check (default without a terminal)" >&2
  echo "  --agents  set up only these agents (default: ask for each; all with --yes)" >&2
  exit 2
}
want=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) yes=1 ;;
    --agents) [ -n "${2:-}" ] || usage; want="$2"; shift ;;
    *) usage ;;
  esac
  shift
done
[ -t 0 ] || yes=1

n=0 title=""
# Exit code 3 = needs_person: its hint must stay the last stderr line.
trap '[ $? = 3 ] || echo "prepare.sh: failed at step $n ($title), see the output above" >&2' ERR

[ -f "$repo_root/$dev_dockerfile" ] || { echo "No $dev_dockerfile in $repo_root: run $(hint "copy dev.Dockerfile prompt") and give the prompt to an agent" >&2; exit 1; }

# Asked up front so the long steps run unattended. --agents or --yes skip the questions.
chosen=() created=()  # created: volumes made by this run, removed again if that agent's login is skipped
new_volume() { docker volume inspect "$1" >/dev/null 2>&1 || created+=("$1"); ensure_volume "$1"; }
if [ -n "$want" ]; then
  IFS=, read -ra chosen <<<"$want"
  for a in "${chosen[@]}"; do
    [[ " ${agents[*]} " == *" $a "* ]] || { echo "Unknown agent '$a' in --agents; known: ${agents[*]}" >&2; exit 2; }
  done
  # Agents not in the list are not set up or checked, and their volumes stay as they are.
  for a in "${chosen[@]}"; do new_volume "$(agent_var "$a" volume)"; done
else
  for a in "${agents[@]}"; do
    label="$(agent_var "$a" label)" volume="$(agent_var "$a" volume)"
    ans=y
    [ -n "$yes" ] || read -r -p "Set up $label in workspaces? [Y/n] " ans
    case "$ans" in
      # An existing volume still enables the agent in workspaces, so its login is checked anyway.
      [nN]*) if docker volume inspect "$volume" >/dev/null 2>&1; then
          chosen+=("$a")
          echo "  Volume '$volume' already exists, so workspaces still use $label; \`docker volume rm $volume\` drops it." >&2
        fi ;;
      *) chosen+=("$a")
        # The volume marks the agent as set up: the base image installs only those agents.
        new_volume "$volume" ;;
    esac
  done
fi

total=$((3 + ${#chosen[@]}))
step() { n=$((n + 1)) title="$1"; printf '\n==> [%s/%s] %s\n' "$n" "$total" "$1" >&2; }

step "Git token (keyring)"
"$here/git-token-setup.sh" ${yes:+--yes}

step "Base image (docker build)"
"$here/docker-base-image.sh"
echo "Image built." >&2

# Interactive: a failed or cancelled (Ctrl+C) login skips only that agent; rerun prepare.sh to retry.
# The INT trap keeps this script alive while Ctrl+C stops the login; children get the default handler.
trap 'echo >&2' INT
for a in ${chosen[@]+"${chosen[@]}"}; do
  step "$(agent_var "$a" label) login (shared Docker volume)"
  if [ -n "$yes" ]; then "$here/$a-login.sh" --yes; continue; fi  # unattended: a failure stops prepare.sh
  "$here/$a-login.sh" && continue
  label="$(agent_var "$a" label)" volume="$(agent_var "$a" volume)"
  if [[ " ${created[*]} " == *" $volume "* ]]; then
    # Without its volume workspaces don't mount the agent, so the self-test doesn't check it.
    docker volume rm "$volume" >/dev/null
    echo "Skipped $label: workspaces won't have it. Rerun $(hint prepare) to set it up." >&2
  else
    echo "Skipped $label: volume '$volume' stays, so workspaces (and the self-test) still check its" \
      "login and fail. Rerun $(hint prepare) to log in, or \`docker volume rm $volume\` to drop it." >&2
  fi
done
trap - INT

# `orca vm recipe doctor` reads only orca.yaml, not plugin recipes: the same create + destroy by hand.
step "Self-test: create + destroy a workspace container (takes a minute)"
result="$(ORCA_VM_INSTANCE_ID="prepare-$(date +%s)" ORCA_RECIPE_RESULT_SCHEMA_VERSION=2 "$here/docker-create.sh")"
jq '{recipeResult: .}' <<<"$result" | "$here/docker-destroy.sh" >/dev/null
echo "Self-test: ok." >&2

printf '\nAll set: Orca can now create "Local Docker" workspaces for this repo.\n' >&2
