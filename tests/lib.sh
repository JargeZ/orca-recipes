# shellcheck shell=bash
# Snapshots this working tree (uncommitted changes included) into a throwaway git repo, so copier
# gets a real commit to record and `copier update` has something to diff against.
commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -qam "$2"; }

export PYTHONWARNINGS=ignore::UserWarning
tmp="$(mktemp -d)"
template="$tmp/template"
rsync -a --exclude .git "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/" "$template/"
git -C "$template" init -q && git -C "$template" add -A && commit "$template" snapshot

render() {  # render <dest> [copier --data args...]
  local dest="$1"; shift
  git init -q "$dest"
  uvx copier copy --quiet --defaults --vcs-ref HEAD "$@" "$template" "$dest" >&2
  git -C "$dest" add -A && commit "$dest" render
}

fail() { echo "FAIL: $*" >&2; exit 1; }
