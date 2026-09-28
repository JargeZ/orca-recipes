<div align="center">

# 🐳 orca-recipes

**Un environnement Docker isolé pour chaque workspace Orca ADE, en un clic**

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

[English](README.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Português (BR)](README.pt-BR.md) · [Español](README.es.md) · **Français**

</div>

---

## ✨ De quoi s'agit-il

Un template de recette pour **Orca ADE** qui crée en un clic un environnement isolé dans votre Docker
local pour chaque workspace.

- 🔐 **Tokens fine-grained pour git** — le token n'a accès qu'à un seul dépôt
- 🤖 **Connexion OAuth des agents** — connectez-vous une fois, ça marche dans tous les workspaces
- 🗝️ **Secrets dans le trousseau système** — macOS Keychain / Linux Secret Service, rien ne finit dans l'image

## 🤖 Agents pris en charge

| Agent | Statut |
|---|---|
| Claude Code | ✅ Oui |
| cursor-agent | 🚧 Bientôt |
| opencode | 🚧 Bientôt |
| …autres | 💡 [Les PR sont bienvenues](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Installation

**Prérequis :** macOS ou Linux, Docker (ou OrbStack), `jq`, `uv`.

**1. Générez le template** à la racine de votre projet :

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> Si vous aviez déjà un `orca.yaml`, le template ne l'écrase pas — ajoutez la recette à la main :
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. Écrivez votre `dev.Dockerfile`** — installez-y toutes les dépendances nécessaires au développement du projet.
Le template crée un exemple pour Python + uv ([template/dev.Dockerfile](template/dev.Dockerfile)) ; adaptez-le
à votre stack. Les exigences de l'image sont dans les commentaires en tête du fichier : base Debian/Ubuntu
uniquement, et tout chemin hors du dépôt où l'installation des dépendances écrit doit appartenir à l'uid 1000.

**3. Lancez le script de préparation** (peut être relancé sans risque) :

```bash
./orca-docker-vm/prepare.sh
```

Il configure le token git, construit l'image de base, connecte Claude et lance un auto-test.
Quand tout est au vert, créez un nouveau workspace depuis l'interface d'Orca et vérifiez qu'il démarre.

En cas de problème, demandez à votre agent de le corriger : après la génération, tout le code de la recette
se trouve dans votre dépôt (`orca-docker-vm/`).

> [!TIP]
> Vous utilisez [Task](https://taskfile.dev) ? Ajoutez `orca: ./orca-docker-vm/Taskfile.yaml` dans `includes`
> et lancez `task orca:setup`.

### 🔄 Mise à jour

Copier met à jour le template par-dessus vos modifications (fusion à trois voies) : récupérer une nouvelle
version de la recette tient en une commande :

```bash
./orca-docker-vm/update.sh                    # dernier tag
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # version précise
```

Les mises à jour ne touchent jamais à `dev.Dockerfile` ni à `orca.yaml`. Plus de détails dans [AGENTS.md](AGENTS.md).

## 🛠️ Développement

Ce projet s'utilise **lui-même** pour son développement dans Orca : clonez le dépôt et lancez-le via Orca
dans des environnements dynamiques.

Le [Taskfile](Taskfile.yaml) est le point d'entrée des tests et des linters :

```bash
task test        # rendu + shellcheck + orca doctor + vérifications d'update (rapide, hors ligne)
task test:e2e    # exécution complète dans Docker : build, create, vérifications SSH, destroy
```

## 🤝 Contribuer

Les pull requests qui rendent le projet **plus universel** (nouveaux agents, images de base, hébergeurs git) sont les bienvenues !
