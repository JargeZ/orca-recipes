# shellcheck shell=bash
# Sourced by the recipe scripts. stdout is reserved for each script's final JSON.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$here/config.sh"

# Where the git token lives, picked per host (ORCA_SECRET_STORE forces one):
#   keychain        macOS Keychain (`security`)
#   secret-service  Linux desktop keyring over D-Bus: GNOME Keyring, KWallet, KeePassXC (`secret-tool`)
#   file            no keyring (headless/SSH host): a 0600 file under ~/.config/orca-docker-vm
secret_store() {
  if [ -n "${ORCA_SECRET_STORE:-}" ]; then echo "$ORCA_SECRET_STORE"
  elif [ "$(uname)" = Darwin ]; then echo keychain
  elif command -v secret-tool >/dev/null && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then echo secret-service
  else echo file
  fi
}
secret_file() { printf '%s/orca-docker-vm/%s' "${XDG_CONFIG_HOME:-$HOME/.config}" "$1"; }

secret_where() {  # secret_where <name>: human-readable location, for messages
  case "$(secret_store)" in
    keychain) echo "macOS Keychain as '$1'" ;;
    secret-service) echo "the desktop keyring (secret-tool) as service '$1'" ;;
    file) echo "file $(secret_file "$1")" ;;
  esac
}

secret_get() {  # secret_get <name>: prints the token, or nothing
  case "$(secret_store)" in
    keychain) security find-generic-password -s "$1" -w 2>/dev/null ;;
    secret-service) secret-tool lookup service "$1" 2>/dev/null ;;
    file) cat "$(secret_file "$1")" 2>/dev/null ;;
    *) echo "Unknown ORCA_SECRET_STORE '$ORCA_SECRET_STORE'" >&2; return 1 ;;
  esac || true
}

secret_set() {  # secret_set <name> <label> <comment> <token>
  case "$(secret_store)" in
    # -l shows in the macOS access prompt; -j in Keychain Access.
    keychain) security add-generic-password -U -s "$1" -a "$USER" -l "$2" -D "Orca token" -j "$3" -w "$4" ;;
    secret-service) printf '%s' "$4" | secret-tool store --label="$2" service "$1" account "$USER" ;;
    file)
      (umask 077 && mkdir -p "$(dirname "$(secret_file "$1")")" && printf '%s' "$4" > "$(secret_file "$1")")
      echo "No keyring on this host: the token is stored in plain text, readable only by $USER." >&2 ;;
    *) echo "Unknown ORCA_SECRET_STORE '$ORCA_SECRET_STORE'" >&2; return 1 ;;
  esac
  echo "Saved to $(secret_where "$1")." >&2
}

# Claude Code's login and state live in a named volume shared by every workspace container, mounted at
# CLAUDE_CONFIG_DIR (set in infra.Dockerfile), as in Anthropic's dev container guide.
claude_mount="$claude_volume:/home/dev/.claude"
claude_run() { docker run --rm -u dev --entrypoint claude -v "$claude_mount" "$@"; }  # claude_run [-it] <image> <args>

# Token scoped to this repo only; never the host's broad `gh auth token`.
git_token() { printf '%s' "${ORCA_GIT_TOKEN:-$(secret_get "$git_token_keychain_service")}"; }

require_git_token() {
  token="$(git_token)"
  [ -n "$token" ] || { echo "No git token: run orca-docker-vm/git-token-setup.sh (or set ORCA_GIT_TOKEN)" >&2; exit 1; }
  export "$git_token_env=$token"
}

# Script for `docker exec bash -s` inside a workspace container as `dev`: fetches repo_ref through the
# image's credential helper, then reruns the project's sync command. The token travels over stdin,
# so it stays out of `docker inspect`.
sync_script() {
  local v
  for v in "$git_token_env" repo_url repo_ref project_root sync_command; do printf 'export %s=%q\n' "$v" "${!v}"; done
  printf '%s' "$remote_sync_script"
}

# shellcheck disable=SC2016
remote_sync_script='set -euo pipefail
export GIT_TERMINAL_PROMPT=0
cd "$project_root"
git fetch origin "$repo_ref"
git checkout -B "$repo_ref" FETCH_HEAD
bash -lc "$sync_command"
'
