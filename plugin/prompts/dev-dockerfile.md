Write `dev.Dockerfile` in the root of this repository. The Orca plugin "Docker VM" builds it as the
base image of each workspace container. On top, the plugin adds sshd, the `dev` user (uid 1000),
git, gh, Claude Code, Cursor Agent, OpenCode and rootless Podman, then copies the repository to
`/home/dev/<repo name>` and runs `ORCA_SYNC_COMMAND` there as `dev`.

Look at the repository first: languages, lock files (uv.lock, poetry.lock, package-lock.json,
pnpm-lock.yaml, yarn.lock, Cargo.lock, go.sum, Gemfile.lock and others), version files
(.python-version, .nvmrc, .tool-versions, rust-toolchain.toml), CI config and existing Dockerfiles.
Use them to find the toolchain, its versions and the system packages the project needs.

Rules:
- Base image: Debian or Ubuntu (the plugin uses apt). Prefer `ubuntu:24.04` or `debian:trixie`.
  Ubuntu 22.04 is too old for Podman compose in the workspace.
- Install only the toolchain and system packages. Do not copy the source code and do not install
  project dependencies: the plugin does that with `ORCA_SYNC_COMMAND`.
- Set `ENV ORCA_SYNC_COMMAND="<command>"`: the command that installs the project's dependencies
  from the repository root, for example `uv sync`, `pnpm install --frozen-lockfile`,
  `npm ci`, `poetry install --with dev`, `bundle install`, `go mod download`. Several steps:
  join them with `&&`. It runs as `dev` (uid 1000) in a login shell.
- Any path the sync command writes outside the repository (a shared venv, a global cache,
  a toolchain dir) must exist and be owned by uid 1000: `RUN mkdir -p /opt/venv && chown 1000:1000 /opt/venv`.
  If the base image has a uid 1000 user (`ubuntu` in ubuntu:24.04), the plugin replaces it with `dev`.
- Toolchains that install per user (nvm, rustup, pyenv) must go to a shared dir owned by uid 1000,
  with their bin dir in `ENV PATH`.
- Every `ENV` you set reaches the agents' SSH sessions. Put the toolchain bin dirs in `PATH` there.
- The build context is the repository root, so `COPY` of a lock or version file works if a step needs it.
- The plugin installs Claude Code, Cursor Agent and OpenCode itself. If the project uses another
  coding agent, install its CLI here too, for all users (not only root), with its bin dir in `PATH`.
- Keep the file short and commented. Do not add an ENTRYPOINT, CMD, USER or EXPOSE.

Example for Python with uv:

```dockerfile
FROM ubuntu:24.04
# uv also installs the Python that the project requires (at sync time).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
# One shared venv: Orca checks out linked worktrees at other paths, and each reuses these deps.
RUN mkdir -p /opt/venv && chown 1000:1000 /opt/venv
ENV VIRTUAL_ENV=/opt/venv \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    ORCA_SYNC_COMMAND="uv sync"
```

When it is written, check it: `docker build -f dev.Dockerfile .` must succeed. Then commit
`dev.Dockerfile` and push it: the workspace image takes only committed files. Then tell me to run
"Docker VM: prepare" from the Orca command palette.
