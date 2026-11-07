<div align="center">

# 🐳 orca-recipes

**One-click isolated Docker environment for every Orca ADE workspace**

[![Last commit](https://img.shields.io/github/last-commit/JargeZ/orca-recipes?style=flat-square)](https://github.com/JargeZ/orca-recipes/commits/main)
[![Commit activity](https://img.shields.io/github/commit-activity/m/JargeZ/orca-recipes?style=flat-square)](https://github.com/JargeZ/orca-recipes/graphs/commit-activity)
[![Release](https://img.shields.io/github/v/tag/JargeZ/orca-recipes?style=flat-square&label=release)](https://github.com/JargeZ/orca-recipes/tags)
[![Stars](https://img.shields.io/github/stars/JargeZ/orca-recipes?style=flat-square)](https://github.com/JargeZ/orca-recipes/stargazers)
[![Issues](https://img.shields.io/github/issues/JargeZ/orca-recipes?style=flat-square)](https://github.com/JargeZ/orca-recipes/issues)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/JargeZ/orca-recipes/pulls)
<br>
[![Copier](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/copier-org/copier/master/img/badge/badge-grayscale-inverted-border-orange.json&style=flat-square)](https://github.com/copier-org/copier)
[![Docker](https://img.shields.io/badge/Docker-local-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Claude Code](https://img.shields.io/badge/Claude_Code-ready-D97757?style=flat-square&logo=anthropic&logoColor=white)](https://code.claude.com)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square)](#)

**English** · [Русский](README.ru.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Português (BR)](README.pt-BR.md) · [Español](README.es.md) · [Français](README.fr.md)

</div>

---

## ✨ What it is

A recipe template for **Orca ADE** that creates an isolated environment in your local Docker for
every workspace, in one click.

- 🔐 **Fine-grained git tokens** — the token is scoped to a single repository
- 🤖 **OAuth login for agents** — log in once, it works in every workspace
- 🗝️ **Secrets in the system keychain** — macOS Keychain / Linux Secret Service, nothing ends up in the image
- 🐳 **Docker inside the workspace** — `docker run/build/compose` via rootless Podman, no `--privileged` (optional)

## 🤖 Supported agents

| Agent | Status |
|---|---|
| Claude Code | ✅ Yes |
| cursor-agent | ✅ Yes |
| opencode (v2) | ✅ Yes |
| …others | 💡 [PRs welcome](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Installation

Two ways, with the same result: the **Orca plugin** (nothing in your repo except `dev.Dockerfile`)
or the **copier template** (the recipe code lives in your repo and you can change it).

### 🧩 As an Orca plugin

**Requirements:** macOS or Linux, Docker (or OrbStack), `jq`, Orca 1.4.248 or later. The repo must
have an `origin` remote on GitHub or GitLab.

1. In Orca: **Settings → Plugins → Add plugin → From a Git URL…** →
   `https://github.com/JargeZ/orca-recipes`, then **Install**, approve and turn it on.
2. No `dev.Dockerfile` yet? Command palette → **Local Docker: copy dev.Dockerfile prompt**, paste it to
   an agent in your repo. It writes `dev.Dockerfile` (with `ENV ORCA_SYNC_COMMAND`, the command that
   installs the deps). Commit and push it.
3. Command palette → **Local Docker: prepare**. It opens a terminal: git token → base image → agent
   logins → self-test. Safe to rerun.
4. Create a workspace: **Run on → Per-Workspace Environment → Local Docker**.

The palette also has **rebuild image** (after a `dev.Dockerfile` or lock change), **git token** and
**log in** for each agent. A repo with its own `docker` recipe in `orca.yaml` (the copier way) keeps
using it.

### 📦 As a copier template

**Requirements:** macOS or Linux, Docker (or OrbStack), `jq`, `uv`.

**1. Render the template** in the root of your project:

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> If you already had an `orca.yaml`, the template won't overwrite it — add the recipe yourself:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     checkoutMode: provisioned-root
>     create: ./.orca-vm/docker-create.sh
>     destroy: ./.orca-vm/docker-destroy.sh
> ```

**2. Write your `dev.Dockerfile`** — install everything your project needs for development.
The template creates a Python + uv example ([template/dev.Dockerfile](template/dev.Dockerfile)); adapt it
to your stack. The image requirements are in the comments at the top of the file: Debian/Ubuntu base
only, and any path outside the repo that dependency installation writes to must be owned by uid 1000.

**3. Run the prepare script** (safe to rerun):

```bash
./.orca-vm/prepare.sh
```

It asks which agents to set up (Claude Code, Cursor Agent, OpenCode), sets up the git token, builds the base image, logs the chosen agents in and runs a self-test.
Without a person (CI, a worker): `./.orca-vm/prepare.sh --yes --agents claude` only checks, see [AGENTS.md](AGENTS.md#unattended-runs).
Once everything is green, create a new workspace in the Orca UI and check that it comes up.

If something goes wrong, ask your agent to fix it: after rendering, all the recipe code lives in
your repository (`.orca-vm/`).

> [!TIP]
> Using [Task](https://taskfile.dev)? Add `orca: ./.orca-vm/Taskfile.yaml` to `includes`
> and run `task orca:setup`.

To create a workspace from a script or an agent instead of the Orca UI, use
`./.orca-vm/workspace.sh add <name>` and `./.orca-vm/workspace.sh rm <name>`. Then use it
in the CLI as `--environment <name>`. See [AGENTS.md](AGENTS.md#workspaces-without-the-orca-ui).

### 🔄 Updating

Copier updates the template on top of your changes (three-way merge), so pulling a new version of
the recipe is one command:

```bash
./.orca-vm/update.sh                    # latest tag
./.orca-vm/update.sh --vcs-ref v1.2.0   # specific version
```

Updates never touch `dev.Dockerfile` or `orca.yaml`. Details are in [AGENTS.md](AGENTS.md).

## 🛠️ Development

This project uses **itself** for development in Orca: clone the repo and run it through Orca in
dynamic environments.

The [Taskfile](Taskfile.yaml) is the entry point for tests and linters:

```bash
task test        # render + shellcheck + orca doctor + update checks (fast, offline)
task test:e2e    # full Docker run: build, create, SSH checks, destroy
task test:plugin-e2e  # the plugin recipe as Orca runs it (after bash plugin/vm/prepare.sh)
```

## 🤝 Contributing

Pull requests that make it **more universal** (new agents, base images, git hosts) are very welcome!

## 📄 License

[MIT](LICENSE): use it any way you like, keeping the copyright notice.
