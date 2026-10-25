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

# Podman (copier `podman`): Docker API on DOCKER_HOST, rootless as dev (infra.Dockerfile). Without the
# docker run flags from docker-create.sh only this service fails, not sshd.
# Subordinate ids of dev: all ids this container has (at most 65536), minus dev's own 1000. A rootless
# Podman host maps fewer, and fewer again when it is itself a container; an id outside the map fails newuidmap.
for kind in uid gid; do
  n=$(awk '{ e = $1 + $3 } e > m { m = e } END { print (m > 65536 ? 65536 : m) }' "/proc/self/${kind}_map")
  printf 'dev:1:999\ndev:1001:%d\n' "$((n - 1001))" > "/etc/sub$kind"
done
install -d -m 700 -o dev -g dev "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/podman"
# shellcheck disable=SC2016  # expands in dev's shell
su dev -c 'exec podman system service --time=0 "$DOCKER_HOST"' >/var/log/podman.log 2>&1 &

exec /usr/sbin/sshd -D -e
