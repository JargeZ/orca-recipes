<div align="center">

# 🐳 orca-recipes

**一键为每个 Orca ADE 工作区创建隔离的 Docker 环境**

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

[English](README.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · **简体中文** · [Português (BR)](README.pt-BR.md) · [Español](README.es.md) · [Français](README.fr.md)

</div>

---

## ✨ 简介

这是一个 **Orca ADE** 的配方(recipe)模板,可一键在本地 Docker 中为每个工作区创建隔离环境。

- 🔐 **Git 细粒度令牌(Fine-grained token)** —— 令牌权限仅限单个仓库
- 🤖 **智能体 OAuth 登录** —— 只需登录一次,所有工作区均可使用
- 🗝️ **密钥保存在系统钥匙串中** —— macOS Keychain / Linux Secret Service,镜像中不含任何密钥

## 🤖 支持的智能体

| 智能体 | 状态 |
|---|---|
| Claude Code | ✅ 支持 |
| cursor-agent | ✅ 支持 |
| opencode (v2) | ✅ 支持 |
| …其他 | 💡 [欢迎 PR](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 安装

**要求:** macOS 或 Linux、Docker(或 OrbStack)、`jq`、`uv`。

**1. 渲染模板**(在项目根目录执行):

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> 如果你已有 `orca.yaml`,模板不会覆盖它——请手动添加配方:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     checkoutMode: provisioned-root
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. 编写 `dev.Dockerfile`** —— 在其中安装项目开发所需的全部依赖。
模板会生成一个 Python + uv 的示例([template/dev.Dockerfile](template/dev.Dockerfile)),请根据你的技术栈调整。
镜像要求写在文件开头的注释中:基础镜像仅支持 Debian/Ubuntu;依赖安装时写入仓库之外的路径必须归 uid 1000 所有。

**3. 运行准备脚本**(可安全地重复运行):

```bash
./orca-docker-vm/prepare.sh
```

它会配置 Git 令牌、构建基础镜像、登录 Claude、Cursor Agent 和 OpenCode 并运行自检。
全部通过后,在 Orca 界面中创建一个新工作区,确认它能正常启动。

如果出了问题,请让你的智能体来修复:模板渲染后,所有配方代码都在你的仓库中(`orca-docker-vm/`)。

> [!TIP]
> 在使用 [Task](https://taskfile.dev)?在 `includes` 中添加 `orca: ./orca-docker-vm/Taskfile.yaml`,
> 然后运行 `task orca:setup`。

### 🔄 更新

Copier 支持在你的修改之上更新模板(三方合并),因此拉取新版配方只需一条命令:

```bash
./orca-docker-vm/update.sh                    # 最新标签
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # 指定版本
```

更新不会改动 `dev.Dockerfile` 和 `orca.yaml`。详情见 [AGENTS.md](AGENTS.md)。

## 🛠️ 开发

本项目在 Orca 中 **用自己来开发自己**:克隆仓库,并通过 Orca 在动态环境中运行。

[Taskfile](Taskfile.yaml) 是测试和代码检查的入口:

```bash
task test        # 渲染 + shellcheck + orca doctor + update 检查(快速、离线)
task test:e2e    # 在 Docker 中完整运行:构建、create、SSH 检查、destroy
```

## 🤝 参与贡献

非常欢迎让项目 **更通用** 的 Pull Request(新的智能体、基础镜像、Git 托管平台)!

## 📄 许可证

[MIT](LICENSE):保留版权声明即可自由使用。
