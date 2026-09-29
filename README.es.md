<div align="center">

# 🐳 orca-recipes

**Un entorno Docker aislado para cada workspace de Orca ADE, en un clic**

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

[English](README.md) · [Русский](README.ru.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Português (BR)](README.pt-BR.md) · **Español** · [Français](README.fr.md)

</div>

---

## ✨ Qué es

Una plantilla de receta para **Orca ADE** que crea en un clic un entorno aislado en tu Docker local
para cada workspace.

- 🔐 **Tokens fine-grained para git** — el token tiene acceso a un solo repositorio
- 🤖 **Login OAuth de los agentes** — inicias sesión una vez y funciona en todos los workspaces
- 🗝️ **Secretos en el llavero del sistema** — macOS Keychain / Linux Secret Service, nada termina en la imagen

## 🤖 Agentes soportados

| Agente | Estado |
|---|---|
| Claude Code | ✅ Sí |
| cursor-agent | 🚧 Próximamente |
| opencode | 🚧 Próximamente |
| …otros | 💡 [Se aceptan PRs](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 Instalación

**Requisitos:** macOS o Linux, Docker (u OrbStack), `jq`, `uv`.

**1. Renderiza la plantilla** en la raíz de tu proyecto:

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> Si ya tenías un `orca.yaml`, la plantilla no lo sobrescribe — añade la receta a mano:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     checkoutMode: provisioned-root
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. Escribe tu `dev.Dockerfile`** — instala en él todas las dependencias necesarias para desarrollar el proyecto.
La plantilla crea un ejemplo para Python + uv ([template/dev.Dockerfile](template/dev.Dockerfile)); adáptalo
a tu stack. Los requisitos de la imagen están en los comentarios al inicio del archivo: base solo Debian/Ubuntu,
y cualquier ruta fuera del repositorio en la que escriba la instalación de dependencias debe pertenecer al uid 1000.

**3. Ejecuta el script de preparación** (se puede volver a ejecutar sin riesgo):

```bash
./orca-docker-vm/prepare.sh
```

Configura el token de git, construye la imagen base, inicia sesión en Claude y ejecuta un autotest.
Cuando todo esté en verde, crea un nuevo workspace desde la interfaz de Orca y comprueba que arranca.

Si algo sale mal, pide a tu agente que lo arregle: tras el renderizado, todo el código de la receta
está en tu repositorio (`orca-docker-vm/`).

> [!TIP]
> ¿Usas [Task](https://taskfile.dev)? Añade `orca: ./orca-docker-vm/Taskfile.yaml` en `includes`
> y ejecuta `task orca:setup`.

### 🔄 Actualización

Copier actualiza la plantilla por encima de tus cambios (merge a tres bandas), así que traer una nueva
versión de la receta es un solo comando:

```bash
./orca-docker-vm/update.sh                    # última etiqueta
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # versión concreta
```

Las actualizaciones nunca tocan `dev.Dockerfile` ni `orca.yaml`. Más detalles en [AGENTS.md](AGENTS.md).

## 🛠️ Desarrollo

Este proyecto se usa **a sí mismo** para desarrollarse en Orca: clona el repositorio y ejecútalo con Orca
en entornos dinámicos.

El [Taskfile](Taskfile.yaml) es el punto de entrada para tests y linters:

```bash
task test        # render + shellcheck + orca doctor + comprobaciones de update (rápido, sin red)
task test:e2e    # ejecución completa en Docker: build, create, comprobaciones SSH, destroy
```

## 🤝 Contribuir

¡Los pull requests que hagan el proyecto **más universal** (nuevos agentes, imágenes base, hosts de git) son muy bienvenidos!

## 📄 Licencia

[MIT](LICENSE): úsalo como quieras, conservando el aviso de copyright.
