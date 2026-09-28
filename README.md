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

## 🤖 Supported agents

| Agent | Status |
|---|---|
| Claude Code | ✅ Yes |
| cursor-agent | 🚧 Soon |
| opencode | 🚧 Soon |
| …others | 💡 [PRs welcome](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Installation

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
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. Write your `dev.Dockerfile`** — install everything your project needs for development.
The template creates a Python + uv example ([template/dev.Dockerfile](template/dev.Dockerfile)); adapt it
to your stack. The image requirements are in the comments at the top of the file: Debian/Ubuntu base
only, and any path outside the repo that dependency installation writes to must be owned by uid 1000.

**3. Run the prepare script** (safe to rerun):

```bash
./orca-docker-vm/prepare.sh
```

It sets up the git token, builds the base image, logs Claude in and runs a self-test.
Once everything is green, create a new workspace in the Orca UI and check that it comes up.

If something goes wrong, ask your agent to fix it: after rendering, all the recipe code lives in
your repository (`orca-docker-vm/`).

> [!TIP]
> Using [Task](https://taskfile.dev)? Add `orca: ./orca-docker-vm/Taskfile.yaml` to `includes`
> and run `task orca:setup`.

### 🔄 Updating

Copier updates the template on top of your changes (three-way merge), so pulling a new version of
the recipe is one command:

```bash
./orca-docker-vm/update.sh                    # latest tag
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # specific version
```

Updates never touch `dev.Dockerfile` or `orca.yaml`. Details are in [AGENTS.md](AGENTS.md).

## 🛠️ Development

This project uses **itself** for development in Orca: clone the repo and run it through Orca in
dynamic environments.

The [Taskfile](Taskfile.yaml) is the entry point for tests and linters:

```bash
task test        # render + shellcheck + orca doctor + update checks (fast, offline)
task test:e2e    # full Docker run: build, create, SSH checks, destroy
```

## 🤝 Contributing

Pull requests that make it **more universal** (new agents, base images, git hosts) are very welcome!
