# TODO

## Block access from a workspace to the host and the local network

**Problem.** A workspace container can open ports on the host and on the LAN. Checked on OrbStack
(2026-11-07) from a plain bridge container: services that listen only on the Mac's `127.0.0.1`
(adb `:5037`, `cef_serve` `:30000`) answer on `host.docker.internal`, and the LAN router
`192.168.4.1:80` answers too. On Linux the host is at the bridge gateway (`172.17.0.1`).

**Approach (prototype works).** Firewall rules in the workspace's own network namespace, set by a
short-lived helper container. The workspace itself never gets `NET_ADMIN`, so root in it (`sudo`)
cannot remove the rules (`iptables -F` → Permission denied).

1. `infra.Dockerfile`: install `iptables` (the helper runs from the workspace image, so create
   downloads nothing).
2. `docker-create.sh`, right after `docker run -d` and before the sync and SSH steps:
   ```bash
   dns="$(docker exec "$name" awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)"
   docker run --rm --net "container:$name" --cap-add NET_ADMIN --entrypoint sh "$image" -c '
     iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT  # replies: SSH from Orca
     iptables -A OUTPUT -o lo -j ACCEPT
     iptables -A OUTPUT -d "$1" -p udp --dport 53 -j ACCEPT
     iptables -A OUTPUT -d "$1" -p tcp --dport 53 -j ACCEPT
     for n in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16 0.0.0.0/8; do
       iptables -A OUTPUT -d "$n" -j REJECT; done
     ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
     ip6tables -A OUTPUT -o lo -j ACCEPT
     for n in fc00::/7 fe80::/10; do ip6tables -A OUTPUT -d "$n" -j REJECT; done' sh "$dns"
   ```
   `0.0.0.0/8` holds OrbStack's `host.docker.internal` (`0.250.250.254`); its DNS (`0.250.250.200`)
   is allowed first. `100.64.0.0/10` is CGNAT and Tailscale; `169.254.0.0/16` is link-local and
   cloud metadata.
3. Allow the IPs of `git_host` (and a user allowlist setting) before the REJECT rules: a
   self-managed GitLab or company services on a private network must stay reachable.
4. `docker-entrypoint.sh`: before `sshd`, refuse to start when `host.docker.internal` or the default
   gateway answers. `docker restart` / `docker start` gives the container a new namespace without
   the rules (checked: 0 rules after a restart), and only `create` runs the helper.
5. Add the checks to `tests/e2e.sh` and `tests/plugin-e2e.sh`: host and LAN closed, internet and the
   published SSH port open, `iptables -F` as root fails.
6. Make the change in both `template/.orca-vm/` and `plugin/vm/`, then `task plugin:build`.

**Why it does not touch the host.** Netfilter rules belong to a network namespace and live in kernel
memory. `--net container:<workspace>` puts the helper into the workspace's namespace
(`net:[4026533041]`, the host's is `net:[4026532281]`), and its `NET_ADMIN` works only there. The
rules stay after the helper exits and go away with the container. Checked: the host namespace's 84
rules (IPv4 and IPv6, without packet counters) are the same before, during and after. On macOS the
"host" is the OrbStack or Docker Desktop VM; the Mac's `pf` is not involved. The only global effect:
the kernel may load the `nf_tables` / `nf_conntrack` / `nf_reject` modules if they are not loaded yet.

**Limits.** A host service on a public IP stays reachable (rare on a laptop). Containers that the
agent starts in the nested Podman go out through the same namespace, so the rules cover them too.

**Rejected alternatives.**
- `--internal` network: blocks the host, but also the internet and port publishing (checked). Needs
  a gateway container with an HTTP(S) proxy and an SSH forward. Worth it only for an egress allowlist.
- Host-side rules (`DOCKER-USER` chain, `pasta --no-map-gw`): Linux only, different per engine, and
  not possible on Docker Desktop or OrbStack.
