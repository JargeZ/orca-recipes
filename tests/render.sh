#!/usr/bin/env bash
# Fast, offline: checks this repo's own rendered recipe (`task render` first) plus fresh renders for
# GitHub and GitLab: lints every script, runs Orca's static recipe doctor, tests `copier update`.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
trap 'rm -rf "$tmp"' EXIT

render "$tmp/gh" -d repo_url=https://github.com/acme/widgets.git -d project_slug=widgets
render "$tmp/gl" -d repo_url=https://gitlab.com/acme/sub/gadgets.git -d project_slug=gadgets -d "sync_command=poetry install --with dev"
render "$tmp/np" -d repo_url=https://github.com/acme/plain.git -d project_slug=plain -d podman=false

for p in "$root" "$tmp/gh" "$tmp/gl" "$tmp/np"; do
  for f in orca.yaml dev.Dockerfile orca-docker-vm/{config.sh,lib.sh,Taskfile.yaml,infra.Dockerfile,.copier-answers.yml}; do
    [ -f "$p/$f" ] || fail "$p: missing $f"
  done
  ls "$p"/orca-docker-vm/*.jinja >/dev/null 2>&1 && fail "$p: unrendered .jinja left"
  (source "$p/orca-docker-vm/lib.sh"; [ "$image" = "localhost/$project_slug-orca" ]) || fail "$p: config.sh does not source"
  (cd "$p/orca-docker-vm" && uvx --from shellcheck-py shellcheck -x -P SCRIPTDIR ./*.sh git-credential-orca)
  if command -v orca >/dev/null; then
    orca vm recipe doctor docker --repo-path "$p" --json \
      | jq -e '.ok and ([.. | objects | select(.status? == "warn" or .status? == "fail")] | length == 0)' >/dev/null \
      || fail "$p: orca doctor reported warn/fail"
  fi
done

(source "$tmp/gh/orca-docker-vm/config.sh"; [ "$git_host/$git_token_env" = github.com/GH_TOKEN ]) || fail "github derivation"
(source "$tmp/gl/orca-docker-vm/config.sh"
 [ "$git_host/$git_token_env" = gitlab.com/GITLAB_TOKEN ] && [ "$sync_command" = "poetry install --with dev" ] \
   && [ "$project_root" = /home/dev/gadgets ]) || fail "gitlab derivation"
render "$tmp/sm" -d repo_url=https://git.example.com/acme/gizmos.git -d project_slug=gizmos
(source "$tmp/sm/orca-docker-vm/config.sh"; [ "$git_host/$git_token_env" = git.example.com/GITLAB_TOKEN ]) || fail "self-managed gitlab derivation"

# podman: on by default, and off leaves no trace of it in the image or entrypoint.
grep -q podman "$tmp/gh/orca-docker-vm/infra.Dockerfile" || fail "podman missing by default"
(source "$tmp/np/orca-docker-vm/config.sh"; [ "$podman" = false ]) || fail "podman=false not in config.sh"
grep -qi podman "$tmp/np/orca-docker-vm/"{infra.Dockerfile,docker-entrypoint.sh} && fail "podman=false still installs podman"

# Shell-special characters in answers survive config.sh quoting.
render "$tmp/q" -d repo_url=https://github.com/acme/q.git -d project_slug=q -d "sync_command=echo 'it'\''s' \$HOME"
(source "$tmp/q/orca-docker-vm/config.sh"; [ "$sync_command" = "echo 'it'\''s' \$HOME" ]) || fail "config quoting"

# Update: template changes land, project-owned edits stay.
echo '# mine' >> "$tmp/gh/dev.Dockerfile"; commit "$tmp/gh" mine
echo '# v2' >> "$template/template/orca-docker-vm/infra.Dockerfile.jinja"; commit "$template" v2
(cd "$tmp/gh" && uvx copier update --quiet --defaults --vcs-ref HEAD -a orca-docker-vm/.copier-answers.yml >&2)
grep -q '# v2' "$tmp/gh/orca-docker-vm/infra.Dockerfile" || fail "update did not apply template change"
grep -q '# mine' "$tmp/gh/dev.Dockerfile" || fail "update clobbered dev.Dockerfile"

# File store (hosts without a keyring): round-trips, and the token file is private.
(export ORCA_SECRET_STORE=file XDG_CONFIG_HOME="$tmp/cfg"; source "$root/orca-docker-vm/lib.sh"
 secret_set t-orca label comment 's3cr3t' 2>/dev/null && [ "$(secret_get t-orca)" = s3cr3t ] \
   && [ "$(stat -c %a "$(secret_file t-orca)" 2>/dev/null || stat -f %Lp "$(secret_file t-orca)")" = 600 ]) \
  || fail "file secret store"

echo "render: ok"
