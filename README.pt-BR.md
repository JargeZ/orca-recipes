<div align="center">

# 🐳 orca-recipes

**Ambiente Docker isolado para cada workspace do Orca ADE, em um clique**

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

[English](README.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · **Português (BR)** · [Español](README.es.md) · [Français](README.fr.md)

</div>

---

## ✨ O que é

Um template de receita para o **Orca ADE** que cria, em um clique, um ambiente isolado no seu Docker
local para cada workspace.

- 🔐 **Tokens fine-grained para o git** — o token tem acesso a um único repositório
- 🤖 **Login OAuth dos agentes** — faça login uma vez e funciona em todos os workspaces
- 🗝️ **Segredos no chaveiro do sistema** — macOS Keychain / Linux Secret Service, nada vai para a imagem

## 🤖 Agentes suportados

| Agente | Status |
|---|---|
| Claude Code | ✅ Sim |
| cursor-agent | 🚧 Em breve |
| opencode | 🚧 Em breve |
| …outros | 💡 [PRs são bem-vindos](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Instalação

**Requisitos:** macOS ou Linux, Docker (ou OrbStack), `jq`, `uv`.

**1. Renderize o template** na raiz do seu projeto:

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> Se você já tinha um `orca.yaml`, o template não vai sobrescrevê-lo — adicione a receita manualmente:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     checkoutMode: provisioned-root
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. Escreva o seu `dev.Dockerfile`** — instale nele todas as dependências necessárias para desenvolver o projeto.
O template cria um exemplo para Python + uv ([template/dev.Dockerfile](template/dev.Dockerfile)); adapte-o
à sua stack. Os requisitos da imagem estão nos comentários no início do arquivo: base apenas Debian/Ubuntu,
e qualquer caminho fora do repositório em que a instalação de dependências escreva deve pertencer ao uid 1000.

**3. Rode o script de preparação** (seguro para rodar de novo):

```bash
./orca-docker-vm/prepare.sh
```

Ele configura o token do git, constrói a imagem base, faz login no Claude e roda um autoteste.
Quando tudo estiver verde, crie um novo workspace pela interface do Orca e confira se ele sobe.

Se algo der errado, peça ao seu agente para corrigir: depois da renderização, todo o código da receita
fica no seu repositório (`orca-docker-vm/`).

> [!TIP]
> Usa [Task](https://taskfile.dev)? Adicione `orca: ./orca-docker-vm/Taskfile.yaml` em `includes`
> e rode `task orca:setup`.

### 🔄 Atualização

O Copier atualiza o template por cima das suas alterações (merge de três vias), então trazer uma nova
versão da receita é um único comando:

```bash
./orca-docker-vm/update.sh                    # tag mais recente
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # versão específica
```

As atualizações nunca mexem em `dev.Dockerfile` nem em `orca.yaml`. Mais detalhes em [AGENTS.md](AGENTS.md).

## 🛠️ Desenvolvimento

Este projeto usa **a si mesmo** para ser desenvolvido no Orca: clone o repositório e rode-o pelo Orca
em ambientes dinâmicos.

O [Taskfile](Taskfile.yaml) é o ponto de entrada para testes e linters:

```bash
task test        # render + shellcheck + orca doctor + checagens de update (rápido, offline)
task test:e2e    # execução completa no Docker: build, create, checagens SSH, destroy
```

## 🤝 Contribuindo

Pull requests que tornem o projeto **mais universal** (novos agentes, imagens base, hosts git) são muito bem-vindos!
