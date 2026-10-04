#!/usr/bin/env bash
# Orca `destroy`: removes the container (with its Podman storage volume) and its known_hosts entry. Lifecycle JSON arrives on stdin.
set -euo pipefail
payload="$(cat)"
resource_id="$(jq -r '.recipeResult.userData.resourceId // empty' <<<"$payload")"
host_key="$(jq -r '.recipeResult.userData.hostKey // empty' <<<"$payload")"
port="$(jq -r '.recipeResult.connection.target.port // empty' <<<"$payload")"
[ -n "$resource_id" ] || { echo "No resource id in lifecycle payload" >&2; exit 1; }

docker rm -fv "$resource_id" >&2  # -v: the Podman storage volume, if any

# Drop the known_hosts entry only if it still belongs to this container.
known_hosts="$HOME/.ssh/known_hosts"
if [ -n "$port" ] && [ -n "$host_key" ] && ssh-keygen -F "[127.0.0.1]:$port" -f "$known_hosts" 2>/dev/null | grep -qF "$host_key"; then
  ssh-keygen -R "[127.0.0.1]:$port" -f "$known_hosts" >/dev/null 2>&1
fi
