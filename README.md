# orca-recipes

A [copier](https://copier.readthedocs.io/) template for Orca
per-workspace environments. Each Orca workspace gets a fresh local Docker container that Orca
reaches over SSH, with the repo checked out, deps installed, and Claude Code, `git` and `gh`
already authenticated.

Each project describes only its own toolchain in `dev.Dockerfile`. The template adds the shared
infrastructure and keeps it updatable with `copier update`.

## How the image is built

```
dev.Dockerfile           project-owned: base image, system packages, language toolchain, ENV
  └─ infra.Dockerfile    template: sshd, `dev` user (uid 1000), Node for Orca's SSH relay,
     │                   gh, task, Claude Code, git credential helper, ENV → SSH sessions
     └─ docker commit    repo cloned to project_root + sync command run as `dev`
          = localhost/<project_slug>-orca    (what every workspace boots from)
```

On each workspace, `docker-create.sh` does the following:

1. Boots a container from that image.
2. Writes the Claude and git tokens into the container's `/etc/environment`.
   The tokens are never stored in the image.
3. Copies your host `git config user.name` and `user.email` into the container.
4. Fetches `repo_ref` and runs the sync command again, in case the lock file moved.
5. Checks over SSH what an Orca session will get: `claude --version` and `git ls-remote`.

`docker-destroy.sh` removes the container and its `known_hosts` entry.

### `dev.Dockerfile` contract

- **Debian or Ubuntu base.** The infra layer uses `apt`, and Orca's relay needs the distro's Node 18+.
- **Sync writes go to paths owned by uid 1000.** The sync command runs as `dev` (uid 1000). Any
  path it writes outside the checkout (a shared venv, caches) must be `chown 1000:1000` in
  `dev.Dockerfile`. If the base image already has a uid 1000 user (for example `ubuntu` in
  `ubuntu:24.04`), the infra layer replaces it with `dev`.
- **`ENV` reaches every SSH session.** Every `ENV` you set is copied into Orca's SSH sessions,
  including login shells.
- **Build context is the repo root.** `COPY` of lock files and similar works.

The starter `dev.Dockerfile` targets Python + uv with a shared venv at `/opt/venv`. The shared venv
exists because Orca checks out linked worktrees at other paths, and each of them reuses the deps
baked into the image.

## Using it in a project

Requirements on the host: macOS (tokens live in the Keychain), Docker or OrbStack, `jq`, `uv`
(for `uvx copier`) and [Task](https://taskfile.dev).

```bash
uvx copier copy gh:JargeZ/orca-recipes .      # or a local path to this repo
```

Copier asks the following questions:

| Question | Default | Meaning |
|---|---|---|
| `project_slug` | folder name | Image name `localhost/<slug>-orca`, default Keychain name |
| `repo_url` | — | HTTPS clone URL; `github.com` or a GitLab host |
| `repo_ref` | `main` | Branch the image and new workspaces start from |
| `project_root` | `/home/dev/<slug>` | Checkout path inside the container |
| `dev_dockerfile` | `dev.Dockerfile` | Your Dockerfile, relative to the repo root |
| `sync_command` | `uv sync` | Installs deps, e.g. `poetry install --with dev` |
| `git_token_keychain_service` | `<slug>-orca-git-token` | Keychain entry with this repo's scoped token |
| `claude_token_keychain_service` | `orca-claude-token` | Keychain entry with the Claude token, shared by all projects |

The copy creates the following files:

- `scripts/orca-vm/`: the recipe. It is template-owned, so change it through the template, not
  locally.
- `scripts/orca-vm/.copier-answers.yml`: your answers and the template version.
- `dev.Dockerfile` and `orca.yaml`: created only if they are missing, and never touched by updates.
  If `orca.yaml` already existed, add this recipe to it:

  ```yaml
  environmentRecipes:
    - id: docker
      name: Local Docker
      create: ./scripts/orca-vm/docker-create.sh
      destroy: ./scripts/orca-vm/docker-destroy.sh
  ```

Include the recipe tasks in the project's `Taskfile.yaml`:

```yaml
includes:
  orca: ./scripts/orca-vm/Taskfile.yaml
```

Then provision:

```bash
task orca:setup          # Claude token → git token → base image → end-to-end self-test
```

| Task | What it does |
|---|---|
| `orca:claude-token` | `claude setup-token` → Keychain (once per machine, ~1 year) |
| `orca:git-token` | Prints where to create a repo-scoped token, verifies it with `git ls-remote`, saves it to the Keychain |
| `orca:base-image` | Rebuilds the image; rerun after `dev.Dockerfile` or dependency changes |
| `orca:check` | `orca vm recipe doctor docker --provision`: real create + destroy |
| `orca:update` | `copier update` to the latest template; pin with `-- --vcs-ref v1.2.0` |

### Tokens

- **Git.** Use a token scoped to one repo: a fine-grained PAT on GitHub (Contents, Pull requests,
  Issues, Workflows: read and write), or a project access token on GitLab. Never use the host's
  broad `gh auth token`: every agent in the container can read the token. Inside the container
  it is exported as `GH_TOKEN` or `GITLAB_TOKEN` (so `gh` or `glab` pick it up), and git uses it
  only for the repo's host. `ORCA_GIT_TOKEN` in the environment overrides the Keychain.
- **Claude.** One long-lived token shared by all projects. `CLAUDE_CODE_OAUTH_TOKEN` in the
  environment overrides the Keychain.

`glab` is not in the infra layer. GitLab projects that want it can install it in `dev.Dockerfile`.

## Updating the template

Releases are git tags. In a project:

```bash
task orca:update                         # latest tag
task orca:update -- --vcs-ref v1.2.0     # specific version
```

Copier re-renders `scripts/orca-vm/` and three-way merges it with your local changes. It leaves
`dev.Dockerfile` and `orca.yaml` alone. After an update that touches `infra.Dockerfile`, run
`task orca:base-image`.

## Developing this template

```
copier.yml       questions, derived values, project-owned files
template/        rendered into the project (`.jinja` files are templated, the rest copied verbatim)
tests/           render.sh (fast, offline), e2e.sh (Docker, network)
```

```bash
task test        # render for GitHub and GitLab, shellcheck, orca doctor, answer quoting,
                 # and an update applying a template change without touching dev.Dockerfile
task test:e2e    # build the image against a real repo, create, check the SSH session, destroy
```

`tests/e2e.sh` defaults to a uv project and reads these environment variables:

- `E2E_REPO_URL`, `E2E_REPO_REF` and `E2E_SYNC` choose the repo, branch and sync command.
- `ORCA_GIT_TOKEN` is the git token. It defaults to `gh auth token`, which is acceptable here
  because the test container is thrown away.
- `CLAUDE_CODE_OAUTH_TOKEN` is the Claude token. It defaults to the Keychain entry named by
  `E2E_CLAUDE_KEYCHAIN`.

The e2e test also asserts that no token ends up in the image config. `docker commit` records
`docker run -e` variables, which is why the sync script receives its values over stdin.
