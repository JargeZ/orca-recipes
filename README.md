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
                         gh, task, Claude Code, git credential helper, ENV → SSH sessions,
                         then the repo at project_root + sync command run as `dev`
          = localhost/<project_slug>-orca    (what every workspace boots from)
```

The checkout in the image is a clone of your **local** repo at `repo_ref` (committed files only),
passed to `docker build` as a named build context. So building needs no token, and no secret ever
enters a build step, a layer or the image config.

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

Requirements on the host: macOS (tokens live in the Keychain), Docker or OrbStack, `jq` and `uv`
(for `uvx copier`).

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

- `orca-docker-vm/`: the recipe. It is template-owned, so change it through the template, not
  locally.
- `orca-docker-vm/.copier-answers.yml`: your answers and the template version.
- `dev.Dockerfile` and `orca.yaml`: created only if they are missing, and never touched by updates.
  If `orca.yaml` already existed, add this recipe to it:

  ```yaml
  environmentRecipes:
    - id: docker
      name: Local Docker
      create: ./orca-docker-vm/docker-create.sh
      destroy: ./orca-docker-vm/docker-destroy.sh
  ```

Then provision:

```bash
./orca-docker-vm/prepare.sh      # Claude token → git token → base image → end-to-end self-test
```

`prepare.sh` is idempotent and just runs the individual scripts in order:

| Script | What it does |
|---|---|
| `claude-token-setup.sh` | `claude setup-token` → Keychain (once per machine, ~1 year; `FORCE=1` to reissue) |
| `git-token-setup.sh` | Prints where to create a repo-scoped token, verifies it with `git ls-remote`, saves it to the Keychain (`FORCE=1` to replace) |
| `docker-base-image.sh` | Rebuilds the image; rerun after `dev.Dockerfile` or dependency changes |
| `update.sh` | `copier update` to the latest template; pin with `--vcs-ref v1.2.0` |

The last step of `prepare.sh` is `orca vm recipe doctor docker --provision`: a real create + destroy.

If the project uses [Task](https://taskfile.dev), the same steps are available as tasks:

```yaml
includes:
  orca: ./orca-docker-vm/Taskfile.yaml
```

`task orca:setup`, `orca:claude-token`, `orca:git-token`, `orca:base-image`, `orca:check`,
`orca:update`.

### Tokens

- **Git.** Use a token scoped to one repo: a fine-grained PAT on GitHub (Contents, Pull requests,
  Issues, Workflows: read and write), or a project access token on GitLab. Never use the host's
  broad `gh auth token`: every agent in the container can read the token. Inside the container
  it is exported as `GH_TOKEN` or `GITLAB_TOKEN` (so `gh` or `glab` pick it up), and git uses it
  only for the repo's host. `ORCA_GIT_TOKEN` in the environment overrides the Keychain.
- **Claude.** One long-lived token shared by all projects. `CLAUDE_CODE_OAUTH_TOKEN` in the
  environment overrides the Keychain.

Tokens exist only at runtime. `docker-create.sh` pipes them over `docker exec` stdin into the
container's `/etc/environment`, so they stay out of the image, `docker inspect` and
`docker history`. Plain `docker run` has no runtime secret mounts (`--secret` is Swarm-only), and
`-e` shows up in `docker inspect`.

`glab` is not in the infra layer. GitLab projects that want it can install it in `dev.Dockerfile`.

## Updating the template

Releases are git tags. In a project:

```bash
./orca-docker-vm/update.sh                    # latest tag
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # specific version
```

Copier re-renders `orca-docker-vm/` and three-way merges it with your local changes. It leaves
`dev.Dockerfile` and `orca.yaml` alone. After an update that touches `infra.Dockerfile`, run
`./orca-docker-vm/docker-base-image.sh`.

## Developing this template

This repo uses its own template: `orca-docker-vm/`, `dev.Dockerfile` and `orca.yaml` at the root
are rendered from `template/`, and the root `Taskfile.yaml` includes `orca:` like a project using Task.

```
copier.yml       questions, derived values, project-owned files
template/        rendered into projects (`.jinja` files are templated, the rest copied verbatim)
orca-docker-vm/  this repo's own render of template/ - don't edit, run `task render`
dev.Dockerfile   this repo's dev image: uv (copier, shellcheck), jq, rsync
tests/           render.sh (fast, offline), e2e.sh (Docker, network)
```

```bash
task render      # copier recopy from the working tree, uncommitted template changes included
task test        # render, then: this repo's recipe + fresh GitHub/GitLab renders get shellcheck,
                 # orca doctor, answer quoting, and an update keeping dev.Dockerfile edits
task test:e2e    # render, then this repo's recipe for real: build, create, SSH checks, destroy
```

`task render` uses `copier recopy`, not `update`: update refuses a dirty repo, and here the template
and the project are the same repo. The image holds committed files only, and `create` fetches
`repo_ref` from GitHub, so the e2e test needs the branch pushed. It reads:

- `ORCA_GIT_TOKEN` is the git token. It defaults to `gh auth token`, which is acceptable here
  because the test container is thrown away.
- `CLAUDE_CODE_OAUTH_TOKEN` is the Claude token. It defaults to the Keychain entry named by
  `E2E_CLAUDE_KEYCHAIN`.

The e2e test also greps the image config and `docker history` for both tokens.
