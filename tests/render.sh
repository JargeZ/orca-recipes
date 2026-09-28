#!/usr/bin/env bash
# Fast, offline: renders for GitHub and GitLab, lints every script, runs Orca's static recipe doctor.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
trap 'rm -rf "$tmp"' EXIT

render "$tmp/gh" -d repo_url=https://github.com/acme/widgets.git -d project_slug=widgets
render "$tmp/gl" -d repo_url=https://gitlab.com/acme/sub/gadgets.git -d project_slug=gadgets -d "sync_command=poetry install --with dev"

for p in "$tmp/gh" "$tmp/gl"; do
  for f in orca.yaml dev.Dockerfile scripts/orca-vm/{config.sh,lib.sh,Taskfile.yaml,infra.Dockerfile,.copier-answers.yml}; do
    [ -f "$p/$f" ] || fail "$p: missing $f"
  done
  ls "$p"/scripts/orca-vm/*.jinja >/dev/null 2>&1 && fail "$p: unrendered .jinja left"
  (source "$p/scripts/orca-vm/lib.sh"; [ "$image" = "localhost/$project_slug-orca" ]) || fail "$p: config.sh does not source"
  (cd "$p/scripts/orca-vm" && uvx --from shellcheck-py shellcheck -x -P SCRIPTDIR ./*.sh git-credential-orca)
  if command -v orca >/dev/null; then
    orca vm recipe doctor docker --repo-path "$p" --json \
      | jq -e '.ok and ([.. | objects | select(.status? == "warn" or .status? == "fail")] | length == 0)' >/dev/null \
      || fail "$p: orca doctor reported warn/fail"
  fi
done

(source "$tmp/gh/scripts/orca-vm/config.sh"; [ "$git_host/$git_token_env" = github.com/GH_TOKEN ]) || fail "github derivation"
(source "$tmp/gl/scripts/orca-vm/config.sh"
 [ "$git_host/$git_token_env" = gitlab.com/GITLAB_TOKEN ] && [ "$sync_command" = "poetry install --with dev" ] \
   && [ "$project_root" = /home/dev/gadgets ]) || fail "gitlab derivation"

# Shell-special characters in answers survive config.sh quoting.
render "$tmp/q" -d repo_url=https://github.com/acme/q.git -d project_slug=q -d "sync_command=echo 'it'\''s' \$HOME"
(source "$tmp/q/scripts/orca-vm/config.sh"; [ "$sync_command" = "echo 'it'\''s' \$HOME" ]) || fail "config quoting"

# Update: template changes land, project-owned edits stay.
echo '# mine' >> "$tmp/gh/dev.Dockerfile"; commit "$tmp/gh" mine
echo '# v2' >> "$template/template/scripts/orca-vm/infra.Dockerfile"; commit "$template" v2
(cd "$tmp/gh" && uvx copier update --quiet --defaults --vcs-ref HEAD -a scripts/orca-vm/.copier-answers.yml >&2)
grep -q '# v2' "$tmp/gh/scripts/orca-vm/infra.Dockerfile" || fail "update did not apply template change"
grep -q '# mine' "$tmp/gh/dev.Dockerfile" || fail "update clobbered dev.Dockerfile"

echo "render: ok"
