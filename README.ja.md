<div align="center">

# 🐳 orca-recipes

**Orca ADE のワークスペースごとに、隔離された Docker 環境をワンクリックで**

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

[English](README.md) · [Русский](README.ru.md) · **日本語** · [简体中文](README.zh-CN.md) · [Português (BR)](README.pt-BR.md) · [Español](README.es.md) · [Français](README.fr.md)

</div>

---

## ✨ 概要

**Orca ADE** 用のレシピテンプレートです。ワークスペースごとに、ローカルの Docker 上に隔離された環境を
ワンクリックで作成します。

- 🔐 **Git 用の Fine-grained トークン** — トークンの権限は 1 つのリポジトリに限定
- 🤖 **エージェントの OAuth ログイン** — 一度ログインすれば、すべてのワークスペースで利用可能
- 🗝️ **シークレットはシステムのキーチェーンに保存** — macOS Keychain / Linux Secret Service。イメージには何も含まれません

## 🤖 対応エージェント

| エージェント | ステータス |
|---|---|
| Claude Code | ✅ 対応 |
| cursor-agent | 🚧 近日対応 |
| opencode | 🚧 近日対応 |
| …その他 | 💡 [PR 歓迎](https://github.com/JargeZ/orca-recipes/pulls) |

## 🚀 インストール

**必要なもの:** macOS または Linux、Docker(または OrbStack)、`jq`、`uv`。

**1. テンプレートをレンダリング** します(プロジェクトのルートで実行):

```bash
uvx copier copy gh:JargeZ/orca-recipes .
```

> [!NOTE]
> すでに `orca.yaml` がある場合、テンプレートは上書きしません。レシピを手動で追加してください:
>
> ```yaml
> environmentRecipes:
>   - id: docker
>     name: Local Docker
>     create: ./orca-docker-vm/docker-create.sh
>     destroy: ./orca-docker-vm/docker-destroy.sh
> ```

**2. `dev.Dockerfile` を記述** します。プロジェクトの開発に必要な依存関係をすべてインストールしてください。
テンプレートは Python + uv のサンプル([template/dev.Dockerfile](template/dev.Dockerfile))を作成するので、
自分のスタックに合わせて調整してください。イメージの要件はファイル冒頭のコメントに記載されています:
ベースイメージは Debian/Ubuntu のみ、依存関係のインストールがリポジトリ外に書き込むパスは uid 1000 の所有である必要があります。

**3. 準備スクリプトを実行** します(何度実行しても安全です):

```bash
./orca-docker-vm/prepare.sh
```

Git トークンの設定、ベースイメージのビルド、Claude へのログイン、セルフテストを行います。
すべて緑になったら、Orca の UI で新しいワークスペースを作成し、起動することを確認してください。

うまくいかない場合は、エージェントに修正を依頼してください。レンダリング後、レシピのコードはすべて
あなたのリポジトリ(`orca-docker-vm/`)にあります。

> [!TIP]
> [Task](https://taskfile.dev) を使っていますか? `includes` に `orca: ./orca-docker-vm/Taskfile.yaml` を追加し、
> `task orca:setup` を実行してください。

### 🔄 アップデート

Copier はあなたの変更の上にテンプレートを更新できる(3-way マージ)ため、新しいバージョンのレシピは
コマンド 1 つで取り込めます:

```bash
./orca-docker-vm/update.sh                    # 最新タグ
./orca-docker-vm/update.sh --vcs-ref v1.2.0   # 特定のバージョン
```

アップデートで `dev.Dockerfile` と `orca.yaml` が変更されることはありません。詳細は [AGENTS.md](AGENTS.md) を参照してください。

## 🛠️ 開発

このプロジェクトは Orca での開発に **自分自身** を使っています。リポジトリをクローンし、
Orca の動的環境で実行してください。

[Taskfile](Taskfile.yaml) がテストとリンターのエントリーポイントです:

```bash
task test        # レンダリング + shellcheck + orca doctor + update のチェック(高速、オフライン)
task test:e2e    # Docker でのフル実行: ビルド、create、SSH チェック、destroy
```

## 🤝 コントリビューション

**汎用性を高める** プルリクエスト(新しいエージェント、ベースイメージ、Git ホスティング)を大歓迎します!
