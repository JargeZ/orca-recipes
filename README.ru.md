<div align="center">

# 🐳 orca-recipes

**Изолированное Docker-окружение на каждый воркспейс Orca ADE — в один клик**

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

[English](README.md) · **Русский** · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Português (BR)](README.pt-BR.md) · [Español](README.es.md) · [Français](README.fr.md)

</div>

---

## ✨ Что это

Шаблон рецепта для **Orca ADE**, который в один клик создаёт изолированное окружение в вашем
локальном Docker для каждого воркспейса.

- 🔐 **Fine-grained токены для git** — токен ограничен одним репозиторием
- 🤖 **OAuth-авторизация агентов** — логинитесь один раз, работает во всех воркспейсах
- 🗝️ **Секреты в системном Keychain** — macOS Keychain / Linux Secret Service, в образ ничего не попадает

## 🤖 Поддерживаемые агенты

| Агент | Статус |
|---|---|
| Claude Code | ✅ Да |
| cursor-agent | 🚧 Скоро |
| opencode | 🚧 Скоро |
| …другие | 💡 [PR welcome](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Установка

**Требования:** macOS или Linux, Docker (или OrbStack), `jq`, `uv`.

**1. Отрендерите шаблон** в корне вашего проекта:

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> Если `orca.yaml` у вас уже был, шаблон его не перезапишет — добавьте рецепт вручную:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. Опишите `dev.Dockerfile`** — установите в нём все зависимости, нужные для разработки проекта.
Шаблон создаст пример для Python + uv ([template/dev.Dockerfile](template/dev.Dockerfile)) — адаптируйте
его под свой стек. Требования к образу описаны в комментариях в начале файла: база только
Debian/Ubuntu, пути вне репозитория, куда пишет установка зависимостей, должны принадлежать uid 1000.

**3. Запустите подготовку** (безопасно для повторных запусков):

```bash
./orca-docker-vm/prepare.sh
```

Скрипт настроит git-токен, соберёт базовый образ, залогинит Claude и прогонит self-test.
Когда всё зелёное — создайте новый воркспейс через интерфейс Orca и проверьте, что он поднимается.

Если что-то пошло не так — попросите агента исправить: после рендера весь код рецепта лежит
у вас в репозитории (`orca-docker-vm/`).

> [!TIP]
> Используете [Task](https://taskfile.dev)? Подключите `orca: ./orca-docker-vm/Taskfile.yaml` в `includes`
> и запускайте `task orca:setup`.

### 🔄 Обновление

Copier умеет обновлять шаблон поверх ваших изменений (трёхсторонний merge), поэтому новую версию
рецепта можно подтянуть одной командой:

```bash
./orca-docker-vm/update.sh                    # последний тег
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # конкретная версия
```

`dev.Dockerfile` и `orca.yaml` при обновлении не трогаются. Подробности — в [AGENTS.md](AGENTS.md).

## 🛠️ Разработка

Проект использует **сам себя** для разработки в Orca: склонируйте репозиторий и запускайте его
через Orca в динамических окружениях.

[Taskfile](Taskfile.yaml) — точка входа для тестов и линтеров:

```bash
task test        # рендер + shellcheck + orca doctor + проверки update (быстро, офлайн)
task test:e2e    # полный прогон в Docker: сборка, create, SSH-проверки, destroy
```

## 🤝 Контрибьюция

Пулл-реквесты, добавляющие **больше универсальности** (новые агенты, базовые образы, git-хостинги),
очень приветствуются!
