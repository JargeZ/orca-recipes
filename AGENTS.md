# orca-recipes: reference for agents and contributors

The detailed reference: how the recipe works, every script, token handling and how to develop the
template. The user-facing overview is in [README.md](README.md).

A [copier](https://copier.readthedocs.io/) template for Orca
per-workspace environments. Each Orca workspace gets a fresh local Docker container that Orca
reaches over SSH, with the repo checked out, deps installed, and Claude Code, Cursor Agent,
OpenCode, `git` and `gh` already authenticated.

Each project describes only its own toolchain in `dev.Dockerfile`. The template adds the shared
infrastructure and keeps it updatable with `copier update`.

## How the image is built

```
dev.Dockerfile           project-owned: base image, system packages, language toolchain, ENV
  └─ infra.Dockerfile    template: sshd, `dev` user (uid 1000), gh, task, Claude Code,
                         Cursor Agent, OpenCode, git credential helper, rootless
                         Podman + Docker CLI (optional), ENV → SSH sessions, then
                         the repo at project_root + sync as `dev`
          = localhost/<project_slug>-orca    (what every workspace boots from)
```

The checkout in the image is a clone of your **local** repo at `repo_ref` (committed files only),
passed to `docker build` as a named build context. So building needs no token, and no secret ever
enters a build step, a layer or the image config.

On each workspace, `docker-create.sh` does the following:

1. Boots a container from that image, with the shared login volume of every agent set up by
   `prepare.sh` mounted (an agent without a volume is skipped). With `podman`, also mounts a fresh
   volume for Podman's storage and sets the flags rootless Podman needs.
2. Writes the git token into the container's `/etc/environment`. The token is never stored in
   the image.
3. Copies your host `git config user.name` and `user.email` into the container.
4. Fetches `repo_ref` and runs the sync command again, in case the lock file moved.
5. Checks over SSH what an Orca session will get: each mounted agent's login (`claude auth status`,
   `agent status`, `opencode auth list`), `docker info` (with `podman`) and `git ls-remote`.

`docker-destroy.sh` removes the container, its Podman storage volume and its `known_hosts` entry.

### Workspaces without the Orca UI

`workspace.sh add <name> [branch]` creates a workspace from a script or an agent. It is
non-interactive: a missing prerequisite or a failed step stops it with a message, and it rolls back
what it already did. The steps are:

1. Runs `docker-create.sh` (schema 2, `ORCA_REPO_BRANCH` = `branch`, default `<name>`, from `repo_ref`).
2. Adds the container to Orca as an SSH host named `<name>` and connects. Orca installs its managed
   server (orcad) and its own Node in `~/.orca-remote` on the container.
3. Adds the checkout at `project_root` as the project's workspace on that server
   (`orca project setup-existing-folder`).

Then the workspace is `--environment <name>` in the CLI, for example
`orca terminal create --environment <name> --worktree path:<project_root>`.
`workspace.sh rm <name>` forgets the server, removes the SSH host and runs `docker-destroy.sh`.
State is in `.orca-vm/.workspaces/<name>.json` (git-ignored).

Orca sees an ordinary SSH host, not a recipe workspace: remove it with `workspace.sh rm`, not from
the Orca UI. Orca has no CLI command to add an SSH host or manage its server, so the script calls
the runtime RPC that the `orca` CLI uses (`ssh.addTarget`, `ssh.connect`, `managedServer.forget`,
`ssh.removeTarget`) through Orca's own client. These methods are internal to Orca and can change in
any release. The script finds Orca from the CLI on `PATH`: `orca` (macOS) or `orca-ide` (Linux).
If it does not find the app binary, set `ORCA_APP_EXECUTABLE`.

### Containers inside a workspace

With the copier answer `podman` (default `true`), agents get `docker run`, `docker build` and
`docker compose` (ports included) inside the workspace. `podman: false` renders the recipe without any
of it. The Podman parts are separate blocks marked `Podman (copier \`podman\`)`: the `{% if podman %}`
blocks in `infra.Dockerfile.jinja` and `docker-entrypoint.sh.jinja` (one `RUN` per step: packages,
user namespace, storage, Docker CLI, `ENV`), and the `$podman` checks in `docker-create.sh` and
`tests/e2e.sh`. The engine is **rootless Podman** running as `dev`. `docker-entrypoint.sh` starts
`podman system service` in the background, and the real Docker CLI and compose plugin talk to it
through `DOCKER_HOST`. The workspace container does **not** run `--privileged`. Classic
Docker-in-Docker, rootless dockerd included, needs `--privileged`, which is root on the Docker VM or
host kernel, where every other container and the agent login volumes live.

`docker-create.sh` passes only what rootless Podman needs and no extra capabilities:
`--security-opt seccomp=unconfined` (Docker's profile blocks the user namespace clone),
`apparmor=unconfined`, `systempaths=unconfined` (nested containers mount `/proc`) and
`--device /dev/net/tun` (slirp4netns/pasta networking). On a Podman host (`host_is_podman` in `lib.sh`)
SELinux labels the container `container_t`, which is denied `/dev/net/tun`: it runs as
`label=type:container_engine_t` instead, SELinux's type for nested engines, which keeps its MCS
categories. That type can't exec the host's `--init` binary, so the image's `catatonit` is the
entrypoint there; on Docker hosts `--init` stays (Docker Engine sets no SELinux labels by default). It also adds an anonymous volume at
`~/.local/share/containers`, because native overlay can't nest on the container's overlay root.
`newuidmap`/`newgidmap` run with file caps instead of setuid, as in `quay.io/podman/stable`: a setuid
one runs as root, not as the user namespace's owner, and gets EPERM without `CAP_SYS_ADMIN`.
The subordinate ids of `dev` are `1-999` and `1001-65535`, not `100000:65536`: a rootless Podman
host maps only 65537 ids into the workspace container.

Limits compared to a real Docker host:
- No BuildKit or buildx: its builder is a privileged container. `DOCKER_BUILDKIT=0` routes `docker build`
  and `docker compose build` to Podman's buildah, which handles normal Dockerfiles, `RUN --mount` included.
- No privileged inner containers, kind/k3d or cgroup limits (`--memory`, `--cpus`).
- The Podman version comes from the `dev.Dockerfile` base: 4.3 on bookworm, 4.9 on Ubuntu 24.04,
  5.x on trixie. Ubuntu 22.04 ships 3.4, which is too old for compose.
- Linux hosts with `kernel.apparmor_restrict_unprivileged_userns=1` (Ubuntu 23.10+) may block the
  inner user namespaces. Set that sysctl to 0 on the host.

### `dev.Dockerfile` contract

- **Debian or Ubuntu base.** The infra layer uses `apt`.
- **Sync writes go to paths owned by uid 1000.** The sync command runs as `dev` (uid 1000). Any
  path it writes outside the checkout (a shared venv, caches) must be `chown 1000:1000` in
  `dev.Dockerfile`. If the base image already has a uid 1000 user (for example `ubuntu` in
  `ubuntu:24.04`), the infra layer replaces it with `dev`.
- **`ENV` reaches every SSH session.** Every `ENV` you set is copied into Orca's SSH sessions,
  including login shells.
- **Build context is the repo root.** `COPY` of lock files and similar works.

The starter `dev.Dockerfile` targets Python + uv on `ubuntu:24.04` with a shared venv at `/opt/venv`;
uv downloads the Python that the project needs. The shared venv exists because Orca checks out linked worktrees at other paths, and each of them reuses the deps
baked into the image.

## Using it in a project

Requirements on the host: macOS or Linux, Docker (or OrbStack), `jq` and `uv` (for `uvx copier`).
The git token is stored in the host keyring, see [Where tokens are stored](#where-tokens-are-stored).

```bash
uvx copier copy gh:JargeZ/orca-recipes .      # or a local path to this repo
```

Copier asks the following questions:

| Question | Default | Meaning |
|---|---|---|
| `project_slug` | folder name | Image name `localhost/<slug>-orca`, default keyring entry names |
| `repo_url` | — | HTTPS clone URL; `github.com`, or any other host = GitLab (gitlab.com or self-managed) |
| `repo_ref` | `main` | Branch the image and new workspaces start from |
| `project_root` | `/home/dev/<slug>` | Checkout path inside the container |
| `dev_dockerfile` | `dev.Dockerfile` | Your Dockerfile, relative to the repo root |
| `sync_command` | `uv sync` | Installs deps, e.g. `poetry install --with dev` |
| `git_token_keychain_service` | `<slug>-orca-git-token` | Keyring entry with this repo's scoped token |
| `claude_volume` | `orca-claude` | Docker volume with the Claude Code login, shared by all projects |
| `cursor_volume` | `orca-cursor` | Docker volume with the Cursor Agent login, shared by all projects |
| `opencode_volume` | `orca-opencode` | Docker volume with the OpenCode login and sessions, shared by all projects |
| `podman` | `true` | Docker inside each workspace via rootless Podman, see [Containers inside a workspace](#containers-inside-a-workspace) |

The copy creates the following files:

- `.orca-vm/`: the recipe. It is template-owned, so change it through the template, not
  locally.
- `.orca-vm/.copier-answers.yml`: your answers and the template version.
- `dev.Dockerfile` and `orca.yaml`: created only if they are missing, and never touched by updates.
  If `orca.yaml` already existed, add this recipe to it:

  ```yaml
  environmentRecipes:
    - id: docker
      name: Local Docker
      create: ./.orca-vm/docker-create.sh
      destroy: ./.orca-vm/docker-destroy.sh
  ```

Then provision:

```bash
./.orca-vm/prepare.sh      # which agents? → git token → base image → agent logins → self-test
```

`prepare.sh` first asks `[Y/n]` for each agent (Claude Code, Cursor Agent, OpenCode); `--agents
claude,cursor` replaces the questions, and agents not in the list are not set up or checked. For each chosen agent it creates the login volume. The image
installs and workspaces mount only the agents whose login volume exists, so answering `n` for an
agent already set up does not remove it (`docker volume rm` and a rebuild do), and its login is still checked. Then it runs the individual scripts in order and says what each step does. Every step checks
first and only asks for input when something is missing or broken, so if anything breaks later (an
expired token, a logged-out agent), rerunning `prepare.sh` fixes it.

### Unattended runs

For callers without a person, such as meta's worker:

```bash
ORCA_GIT_TOKEN=<token> ./.orca-vm/prepare.sh --yes --agents claude
```

`--yes` (also when stdin is not a terminal) asks nothing and never runs `docker run -it`. Without
`--agents` it sets up all agents. The steps that need a person become checks: `git-token-setup.sh`
and `<id>-login.sh` take `--yes` too. When a check fails, the script exits with code 3 and the last
stderr line says what is wrong and what to run by hand, for example `Claude Code is not logged in:
run .orca-vm/claude-login.sh on <host>`. Other failures exit with a different non-zero code. The
token is never printed. An unknown flag stops `prepare.sh` with usage.

A set `ORCA_GIT_TOKEN` is checked with `git push --dry-run` and the keyring is not used, also
without `--yes`.

| Script | What it does |
|---|---|
| `git-token-setup.sh` | Prints where to create a repo-scoped token, verifies it with a `git push --dry-run`, saves it to the keyring (`FORCE=1` to replace; `--yes` or a set `ORCA_GIT_TOKEN`: check only) |
| `docker-base-image.sh` | Rebuilds the image with the agents that have a login volume; rerun after `dev.Dockerfile`, dependency or agent changes |
| `claude-login.sh` | Checks the Claude login with a one-line request; if it fails, runs `claude auth login` in a container (`FORCE=1` to redo, `--yes`: check only) |
| `cursor-login.sh` | Checks Cursor Agent auth status; if it fails, runs `agent login` in a container (`FORCE=1` to redo, `--yes`: check only) |
| `opencode-login.sh` | Checks OpenCode has a saved integration (`auth list`); if not, runs `opencode auth login` in a container (`FORCE=1` to redo, `--yes`: check only) |
| `update.sh` | `copier update` to the latest template; pin with `--vcs-ref v1.2.0` |

The last step of `prepare.sh` is `orca vm recipe doctor docker --provision`: a real create + destroy.

If the project uses [Task](https://taskfile.dev), the same steps are available as tasks:

```yaml
includes:
  orca: ./.orca-vm/Taskfile.yaml
```

`task orca:setup`, `orca:claude-login`, `orca:cursor-login`, `orca:opencode-login`, `orca:git-token`,
`orca:base-image`, `orca:check`, `orca:update`.

### Tokens

- **Git.** Use a token scoped to one repo: a fine-grained PAT on GitHub (Contents, Pull requests,
  Issues, Workflows: read and write); on GitLab a project access token (gitlab.com: Premium+) or a
  fine-grained personal access token limited to the project. Never use the host's
  broad `gh auth token`: every agent in the container can read the token. Inside the container
  it is exported as `GH_TOKEN` or `GITLAB_TOKEN` (so `gh` or `glab` pick it up), and git uses it
  only for the repo's host. `ORCA_GIT_TOKEN` in the environment overrides the keyring.
- **Claude.** A normal `claude auth login` (OAuth, refreshed by Claude Code itself), the way
  [Anthropic's dev container guide](https://code.claude.com/docs/en/devcontainer#persist-authentication-and-settings-across-rebuilds)
  persists it: a named Docker volume (`orca-claude`) that every workspace container mounts at
  `/home/dev/.claude`, with `CLAUDE_CONFIG_DIR` pointing there. You log in once for all projects
  via `claude-login.sh`; nothing is taken from the host Claude login. Session history and settings
  in that directory are shared between workspaces too. Unlike a `claude setup-token` token,
  this login also supports Remote Control and claude.ai connectors. The volume holds a refresh
  token that agents in the container can read; revoke it with `/logout` if needed.
- **Cursor Agent.** A normal `agent login` (OAuth) into a separate named Docker volume
  (`orca-cursor`) mounted at `/home/dev/.config/cursor`, with `CURSOR_CONFIG_DIR` pointing there.
  The image sets `AGENT_CLI_CREDENTIAL_STORE=file` so tokens land in `auth.json` on that volume
  (the default OS keychain store is unavailable in containers). Log in once via `cursor-login.sh`
  for all projects; the host Cursor IDE login is never copied or mounted. Revoke with
  `agent logout` inside a container that mounts the volume.
- **OpenCode (v2).** A normal `opencode auth login` (any provider: OAuth, device code or API key)
  into a named Docker volume (`orca-opencode`) mounted at OpenCode's data dir
  `/home/dev/.local/share/opencode`. v2 no longer writes `auth.json`: credentials live in the SQLite
  db `opencode.db` in that dir, next to sessions, so session history is shared between workspaces too.
  The global config dir (`~/.config/opencode`) is not persisted; keep project config in the repo.
  Log in once via `opencode-login.sh` for all projects; the host OpenCode login is never copied.
  Revoke with `opencode auth logout` inside a container that mounts the volume.

### Adding an agent

Agents are listed in `agents=(...)` in `template/.orca-vm/lib.sh`; `prepare.sh`,
`docker-create.sh` and `tests/e2e.sh` loop over that list. For a new agent `<id>`:

1. `copier.yml`: question `<id>_volume` (default `orca-<id>`); `config.sh.jinja`: `<id>_volume=...`.
2. `lib.sh`: add `<id>` to `agents`, then `<id>_label`, `<id>_mount` (volume → the dir holding its
   login), `<id>_check` (shell run over SSH, exits non-zero when logged out) and `<id>_run`.
3. `infra.Dockerfile`: in the agents `RUN`, under `if has <id>`, install it as `dev` and `mkdir -p`
   the mount dir (a new volume copies its owner); add any `ENV` it needs to find its config there,
   and its bin dir in `PATH`.
4. `<id>-login.sh`, copied from `cursor-login.sh`: check, otherwise log in with `<id>_run -it`.
5. `Taskfile.yaml`: an `<id>-login` task; docs: this file and the README agent tables.

### Where tokens are stored

The scripts choose the store for the host automatically. `ORCA_SECRET_STORE=keychain|secret-service|file`
forces one.

| Host | Store |
|---|---|
| macOS | Keychain (`security`) |
| Linux desktop | Secret Service over D-Bus through `secret-tool` (package `libsecret-tools` / `libsecret`): GNOME Keyring, KWallet 5.97+, KeePassXC |
| No keyring (headless, SSH session, no D-Bus) | `~/.config/orca-docker-vm/<entry>`, mode 0600, plain text |

On hosts with no keyring, `ORCA_GIT_TOKEN` in the environment also
works: `docker-create.sh` reads them before any store. Orca must pass it to the recipe, for example
from a secrets manager in your shell profile.

The git token exists only at runtime. `docker-create.sh` pipes it over `docker exec` stdin into the
container's `/etc/environment`, so it stays out of the image, `docker inspect` and
`docker history`. Plain `docker run` has no runtime secret mounts (`--secret` is Swarm-only), and
`-e` shows up in `docker inspect`.

Any host other than `github.com` is treated as GitLab (gitlab.com or self-managed): the infra layer
also installs `glab`, and `docker-create.sh` sets `GITLAB_HOST` so `glab`
talks to the repo's host.

## Updating the template

Releases are git tags. In a project:

```bash
./.orca-vm/update.sh                    # latest tag
./.orca-vm/update.sh --vcs-ref v1.2.0   # specific version
```

Copier re-renders `.orca-vm/` and three-way merges it with your local changes. It leaves
`dev.Dockerfile` and `orca.yaml` alone. After an update that touches `infra.Dockerfile`, run
`./.orca-vm/docker-base-image.sh`.

Projects made before the recipe moved to `.orca-vm/` run the old `./orca-docker-vm/update.sh`. The
update moves the recipe to `.orca-vm/`, but `orca.yaml` and a Taskfile `includes` still point to
`orca-docker-vm/`. Copier prints the fix after the update: replace the path in those files, then
remove `orca-docker-vm/` (only the git-ignored `.ssh/` key stays there; `docker-create.sh` makes a
new one).

## Developing this template

This repo uses its own template: `.orca-vm/`, `dev.Dockerfile` and `orca.yaml` at the root
are rendered from `template/`, and the root `Taskfile.yaml` includes `orca:` like a project using Task.

```
copier.yml       questions, derived values, project-owned files
template/        rendered into projects (`.jinja` files are templated, the rest copied verbatim)
.orca-vm/        this repo's own render of template/ - don't edit, run `task render`
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
`repo_ref` from GitHub, so the e2e test needs the branch pushed. It uses the Claude, Cursor and
OpenCode login volumes (run `claude-login.sh`, `cursor-login.sh` and `opencode-login.sh` first) and reads `ORCA_GIT_TOKEN` as
the git token, defaulting to `gh auth token`, which is acceptable here because the test container
is thrown away.

The e2e test also greps the image config and `docker history` for the git token.
