#!/usr/bin/env bash
set -euo pipefail

# Generates only missing keys: unique per container, stable across restarts.
ssh-keygen -A

if [ -n "${ORCA_SSH_PUBLIC_KEY:-}" ]; then
  install -d -m 700 -o dev -g dev /home/dev/.ssh
  printf '%s\n' "$ORCA_SSH_PUBLIC_KEY" > /home/dev/.ssh/authorized_keys
  chown dev:dev /home/dev/.ssh/authorized_keys
  chmod 600 /home/dev/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D -e
