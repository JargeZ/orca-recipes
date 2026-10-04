# shellcheck shell=bash disable=SC2034
# Rendered by copier from orca-docker-vm/.copier-answers.yml; edit answers via `orca-docker-vm/update.sh`.
project_slug='orca-recipes'
image="localhost/${project_slug}-orca"
repo_url='https://github.com/JargeZ/orca-recipes.git'
repo_ref='main'
project_root='/home/dev/orca-recipes'
dev_dockerfile='dev.Dockerfile'
sync_command='uvx copier --version && uvx --from shellcheck-py shellcheck --version'
git_host='github.com'
# Name the token gets inside the container, so the host's CLI (gh/glab) finds it too.
git_token_env='GH_TOKEN'
git_token_keychain_service='orca-recipes-orca-git-token'
# Docker volume with the Claude Code login, shared by all projects.
claude_volume='orca-claude'
# Docker volume with the Cursor Agent login, shared by all projects.
cursor_volume='orca-cursor'
# Docker volume with the OpenCode login and sessions, shared by all projects.
opencode_volume='orca-opencode'
# Rootless Podman + Docker CLI inside each workspace (true/false).
podman=true
