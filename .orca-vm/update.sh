#!/usr/bin/env bash
# Hand-run: pulls the latest recipe template (copier 3-way merge). Extra args go to copier,
# e.g. `./.orca-vm/update.sh --vcs-ref v1.2.0`.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
uvx copier update -a .orca-vm/.copier-answers.yml "$@"
