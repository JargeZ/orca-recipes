#!/usr/bin/env bash
# Hand-run: provisions everything the "Local Docker" Orca recipe needs (idempotent).
# Asks which agents to set up, then: git token → base image → each chosen agent's login → end-to-end
# self-test (real create + destroy). Every step checks first and only asks for input when something is
# missing or broken, so rerunning it is how you fix things.
# Unattended (meta): prepare.sh --yes --agents claude. See parse_yes in lib.sh.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
root="$(git -C "$here" rev-parse --show-toplevel)"

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

# Found before the long steps: the last one (doctor) needs it.
orca_cli="$(find_orca)" || exit 1

# Orca matches a workspace's checkout (origin = repo_url) to the project by owner/repo; a mismatch
# with the local origin fails with "Imported folder does not match the selected project identity".
# Host is ignored so SSH aliases (git@github-work:...) still match.
repo_path() { sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@/]+@[^:]+:##; s#\.git$##; s#/+$##' <<<"$1" | tr '[:upper:]' '[:lower:]'; }
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
if [ -n "$origin" ] && [ "$(repo_path "$origin")" != "$(repo_path "$repo_url")" ]; then
  echo "repo_url ($repo_url) and the local origin ($origin) are different repos; Orca won't match" \
    "workspaces to this project. Fix repo_url with .orca-vm/update.sh or the origin remote." >&2
  false
fi

# Asked up front so the long steps run unattended. --agents or --yes skip the questions.
chosen=()
if [ -n "$want" ]; then
  IFS=, read -ra chosen <<<"$want"
  for a in "${chosen[@]}"; do
    [[ " ${agents[*]} " == *" $a "* ]] || { echo "Unknown agent '$a' in --agents; known: ${agents[*]}" >&2; exit 2; }
  done
  # Agents not in the list are not set up or checked, and their volumes stay as they are.
  for a in "${chosen[@]}"; do ensure_volume "$(agent_var "$a" volume)"; done
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
        ensure_volume "$volume" ;;
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

for a in ${chosen[@]+"${chosen[@]}"}; do
  step "$(agent_var "$a" label) login (shared Docker volume)"
  "$here/$a-login.sh" ${yes:+--yes}
done

step "orca vm recipe doctor: real create + destroy of a workspace (takes a minute)"
report="$("$orca_cli" vm recipe doctor docker --repo-path "$root" --provision --json || true)"
if ! jq -e '.ok' >/dev/null 2>&1 <<<"$report"; then
  echo "Doctor reported a problem:" >&2
  jq . <<<"$report" >&2 2>/dev/null || echo "$report" >&2
  false
fi
echo "Doctor: ok." >&2

printf '\nAll set: Orca can now create "Local Docker" workspaces for this repo.\n' >&2
