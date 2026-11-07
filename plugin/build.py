#!/usr/bin/env python3
"""Builds plugin/recipes/docker.json, the recipe Orca reads, from plugin/vm/.

Orca runs a plugin recipe phase as `sh -c <command>` in the repo root and does not tell it where the
plugin is, so each phase carries its scripts: it writes them once to a cache dir named by their hash,
then runs them there. stdin (Orca's lifecycle payload) stays free for the script.

  python3 plugin/build.py           write plugin/recipes/docker.json
  python3 plugin/build.py --check   fail if it is stale
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).parent
vm = root / "vm"
out = root / "recipes" / "docker.json"
MAX = 32 * 1024  # Orca's limit per recipe command
EOF = "ORCA_EOF"


def phase(name: str, files: list[str]) -> str:
    texts = {f: (vm / f).read_text() for f in files}
    digest = hashlib.sha256("".join(f + texts[f] for f in files).encode()).hexdigest()[:12]
    lines = [
        "set -euo pipefail",
        f'd="${{XDG_CACHE_HOME:-$HOME/.cache}}/orca-docker/{digest}"',
        'if [ ! -d "$d" ]; then',
        '  mkdir -p "${d%/*}"',
        '  t="$(mktemp -d "${d%/*}/.tmp.XXXXXX")"',
    ]
    for f, text in texts.items():
        if f"\n{EOF}\n" in f"\n{text}":
            sys.exit(f"{f} has a line {EOF}")
        lines += [f"cat > \"$t/{f}\" <<'{EOF}'", text.rstrip("\n"), EOF]
    lines += [
        '  chmod +x "$t"/*.sh',
        '  [ -d "$d" ] || mv "$t" "$d"; rm -rf "$t"  # another phase may have unpacked it meanwhile',
        "fi",
        f'exec bash "$d/{files[-1]}"',
    ]
    script = "\n".join(lines)
    # One single-quoted argument with each ' as '\''. Not a heredoc inside $(...): macOS /bin/sh is
    # bash 3.2, which misparses an apostrophe in a heredoc there.
    command = "bash -c '" + script.replace("'", "'\\''") + f"' docker-{name}"
    size = len(command.encode())
    if size > MAX:
        sys.exit(f"{name} is {size} bytes, over {MAX}")
    return command


recipe = {
    "schemaVersion": 1,
    "id": "docker",
    "name": "Docker VM",
    "description": "One container on this machine per workspace, not privileged, with a git token for this"
    " repository only and Docker inside through rootless Podman. Set up with \"Docker VM: prepare\".",
    "checkoutMode": "provisioned-root",
    "create": phase("create", ["config.sh", "lib.sh", "docker-create.sh"]),
    "destroy": phase("destroy", ["docker-destroy.sh"]),
}
text = json.dumps(recipe, indent=2, ensure_ascii=False) + "\n"
if "--check" in sys.argv:
    if not out.exists() or out.read_text() != text:
        sys.exit(f"{out} is stale: run python3 plugin/build.py")
    print(f"{out.relative_to(root.parent)} is up to date")
else:
    out.write_text(text)
    for p in ("create", "destroy"):
        print(f"{p}: {len(recipe[p].encode())} bytes")
    print(f"wrote {out.relative_to(root.parent)}")
