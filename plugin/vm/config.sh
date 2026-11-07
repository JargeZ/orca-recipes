# shellcheck shell=bash disable=SC2034
# Plugin config: no copier answers, every value comes from the repo at run time. The project gives
# only dev.Dockerfile (and ENV ORCA_SYNC_COMMAND in it). Orca runs recipe phases in the repo root with
# ORCA_REPO_PATH set; the palette commands run in the repo root too.
repo_root="${ORCA_REPO_PATH:-$(git rev-parse --show-toplevel)}"
origin="$(git -C "$repo_root" remote get-url origin 2>/dev/null)" \
  || { echo "No origin remote in $repo_root: the workspace clones the repo from it" >&2; exit 1; }
# git@host:owner/repo(.git), ssh://git@host/owner/repo, https://host/owner/repo → https://host/owner/repo.git
repo_url="$(sed -E 's#^[a-z+]+://([^@/]+@)?#https://#; s#^[^@/:]+@([^:]+):#https://\1/#; s#\.git$##; s#/+$##' <<<"$origin").git"
git_host="$(cut -d/ -f3 <<<"$repo_url")"
project_slug="$(basename "$repo_url" .git | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_.-\n' '-')"
image="localhost/${project_slug}-orca"
# The branch the image and new workspaces start from: Orca's ref, else origin's default branch.
default_ref="$(git -C "$repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
repo_ref="${ORCA_REPO_REF:-${default_ref#origin/}}"
repo_ref="${repo_ref:-main}"
project_root="/home/dev/$project_slug"
dev_dockerfile=dev.Dockerfile
# Only github.com is GitHub; any other host is GitLab (gitlab.com or self-managed).
if [ "$git_host" = github.com ]; then git_token_env=GH_TOKEN; else git_token_env=GITLAB_TOKEN; fi
git_token_keychain_service="${project_slug}-orca-git-token"
# Login volumes, shared by all projects (the same names as the copier recipe uses).
claude_volume=orca-claude
cursor_volume=orca-cursor
opencode_volume=orca-opencode
# Per-project state outside the repo: the SSH key Orca connects with.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/orca-docker/$project_slug"
# How a message names a step the person runs: a command palette entry of the plugin.
hint() { printf '"Local Docker: %s" in the Orca command palette' "$1"; }
