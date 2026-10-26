#!/usr/bin/env bash
# Adds or removes a workspace container without the Orca UI, for scripts and agents:
#   workspace.sh add <name> [branch]   create (docker-create.sh), register it in Orca as an SSH host,
#                                      connect (Orca installs its server there), add the checkout
#   workspace.sh rm <name>             undo all of that and remove the container
# Then use it by name: orca terminal create --environment <name> --worktree path:<project_root>
# Non-interactive: a missing prerequisite exits non-zero with what to do. A failed add rolls back.
# Not a recipe workspace: Orca sees an SSH host, so remove it with `rm`, not from the Orca UI.
# The SSH host goes through the runtime RPC the orca CLI uses (no CLI commands for it); these
# methods are internal to Orca and may change between releases.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

die() { echo "workspace.sh: $*" >&2; exit 1; }
usage() { die "usage: workspace.sh add <name> [branch] | rm <name>"; }

cmd="${1:-}" name="${2:-}"
[ -n "$name" ] || usage
[[ "$name" =~ ^[a-z0-9][a-z0-9_.-]{0,40}$ ]] || die "name '$name': lowercase letters, digits, . _ - only (max 41)"
for c in jq docker; do command -v "$c" >/dev/null || die "'$c' is not on PATH"; done
state_dir="$here/.workspaces"
state="$state_dir/$name.json"

# The orca CLI (find_orca in lib.sh). It is a launcher in <resources>/bin, often behind a symlink
# (/usr/local/bin/orca). The Linux AppImage registers a stable launcher script instead
# (~/.cache/orca/appimage/launcher/orca-ide) that execs its sibling symlink `installed`.
orca_cli="$(find_orca)" || exit 1
orca() { "$orca_cli" "$@"; }
p="$orca_cli"
while :; do
  if [ -L "$p" ]; then l="$(readlink "$p")"; [[ "$l" = /* ]] && p="$l" || p="$(dirname "$p")/$l"
  elif [ -L "$(dirname "$p")/installed" ]; then p="$(dirname "$p")/installed"
  else break; fi
done
orca_res="$(cd "$(dirname "$p")/.." && pwd)"
# Orca's own runtime client, run on the app's Electron as Node, as the launcher does. The app binary:
# Orca.app/Contents/MacOS/Orca on macOS, next to resources/ on Linux.
orca_exe="${ORCA_APP_EXECUTABLE:-}"
if [ -z "$orca_exe" ]; then
  for e in "$orca_res/../MacOS/Orca" "$orca_res/../orca-ide" "$orca_res/../orca" "$orca_res/../Orca"; do
    [ -f "$e" ] && [ -x "$e" ] && { orca_exe="$e"; break; }
  done
fi
[ -n "$orca_exe" ] || die "Orca app binary not found next to $orca_res (from $orca_cli): set ORCA_APP_EXECUTABLE"
orca_client="$orca_res/app.asar.unpacked/out/cli/runtime/client.js"
[ -f "$orca_client" ] || die "Orca runtime client not found at $orca_client"
# shellcheck disable=SC2016  # JS
rpc() {  # rpc <method> [params-json] [timeout-ms]: prints .result, exits non-zero on any error
  ELECTRON_RUN_AS_NODE=1 "$orca_exe" -e '
    const [client, method, params, timeoutMs] = process.argv.slice(1)
    const { RuntimeClient } = require(client)
    new RuntimeClient().call(method, params ? JSON.parse(params) : undefined, { timeoutMs: Number(timeoutMs) })
      .then(r => console.log(JSON.stringify(r.result)))
      .catch(e => { console.error(`Orca ${method}: ${e.message}`); process.exit(1) })' \
    "$orca_client" "$1" "${2:-}" "${3:-60000}"
}

remove() {
  [ -f "$state" ] || die "no workspace '$name' (no $state)"
  local env target
  env="$(jq -r '.environmentId // empty' "$state")"
  target="$(jq -r '.targetId // empty' "$state")"
  # Forget, not stop: the container goes away below, nothing on it needs cleaning.
  [ -z "$env" ] || orca environment forget --environment "$env" --yes --json >/dev/null \
    || echo "Orca server '$name' was not forgotten, continuing" >&2
  [ -z "$target" ] || rpc ssh.removeTarget "$(jq -nc --arg t "$target" '{targetId: $t}')" >/dev/null \
    || echo "SSH host '$name' was not removed from Orca, continuing" >&2
  jq '{recipeResult: .result}' "$state" | "$here/docker-destroy.sh" >/dev/null
  rm -f "$state"
  echo "Removed workspace '$name'." >&2
}

add() {
  local branch="${1:-$name}" result target env repo project
  [ ! -f "$state" ] || die "workspace '$name' exists ($state): remove it with 'workspace.sh rm $name'"
  rpc ssh.listTargets >/dev/null || die "Orca is not reachable: start the Orca app"
  rpc ssh.listTargets | jq -e --arg n "$name" 'all(.targets[]; .label != $n)' >/dev/null \
    || die "Orca already has an SSH host named '$name'"
  orca environment list --json | jq -e --arg n "$name" '[.. | objects | select(.name? == $n)] == []' >/dev/null \
    || die "Orca already has a server named '$name'"
  # Orca's project id for repo_url: an existing project with this remote, else Orca's own spelling.
  repo="${repo_url#https://}"; repo="${repo%.git}"
  project="$(orca project list --json | jq -r --arg k "$repo" \
    'first(.result.projects[] | select(.gitRemoteIdentity.canonicalKey? // "" | ascii_downcase == ($k | ascii_downcase)) | .id) // empty')"
  if [ -z "$project" ]; then
    case "$repo" in github.com/*) project="github:${repo#github.com/}" ;; *) project="git:$repo" ;; esac
    project="$(tr '[:upper:]' '[:lower:]' <<<"$project")"
  fi

  mkdir -p "$state_dir"
  trap '[ -n "${ok:-}" ] || { echo "Adding failed, rolling back." >&2; [ ! -f "$state" ] || remove || true; }' EXIT
  # The workspace branch starts at repo_ref, as a new Orca workspace does.
  result="$(ORCA_VM_INSTANCE_ID="$name" ORCA_RECIPE_RESULT_SCHEMA_VERSION=2 ORCA_REPO_BRANCH="$branch" "$here/docker-create.sh")"
  jq -n --argjson r "$result" '{result: $r}' > "$state"

  target="$(rpc ssh.addTarget "$(jq -c --arg n "$name" '{target: (.result.connection.target + {label: $n})}' "$state")" | jq -er .target.id)"
  jq --arg t "$target" '. + {targetId: $t}' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
  # First connect installs Orca's server and its Node on the container: allow for the download.
  env="$(rpc ssh.connect "$(jq -nc --arg t "$target" '{targetId: $t}')" 600000 \
    | jq -er 'select(.state.status == "connected") | .state.managedServer.environmentId // empty')" \
    || die "SSH host '$name' did not connect to an Orca server: see Settings > SSH Hosts in Orca"
  jq --arg e "$env" '. + {environmentId: $e}' "$state" > "$state.tmp" && mv "$state.tmp" "$state"

  orca project setup-existing-folder --project "$project" --host "runtime:$env" --path "$project_root" \
    --kind git --display-name "$name" --json >/dev/null \
    || die "Orca did not add $project_root on '$name' as project $project"
  ok=1
  echo "Workspace '$name' ready (branch $branch). Use it with: orca <command> --environment $name --worktree path:$project_root" >&2
}

case "$cmd" in
  add) add "${3:-}" ;;
  rm) remove ;;
  *) usage ;;
esac
