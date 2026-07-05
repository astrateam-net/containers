# astravaultnet

Infisical **Networking** (gateway *or* relay) packaged as a single, env-driven
container image. Thin wrapper over the official [`infisical/cli`](https://hub.docker.com/r/infisical/cli)
image — it adds an entrypoint that dispatches on one variable, resolves Docker /
Swarm secrets, and maps a clean env interface onto the CLI flags that have no
env of their own.

One container runs **one role**, selected by `ASTRAVAULT_NET=gateway|relay`.

```
gateway  ──outbound SSH tunnel──▶  relay  ──▶  Infisical platform (astravault)
(near your resources)              (public host, static IP/DNS)
```

## Base image / building blocks

`FROM infisical/cli:<version>` — the leanest available block: Alpine + `tini`
(PID 1) + the statically linked `infisical` binary, published multi-arch
(amd64/arm64) by Infisical. We add only two POSIX shell scripts; every runtime
dependency (`sh`, `nc`, `pgrep`) is already in busybox. `VERSION` in
`docker-bake.hcl` tracks the CLI release and is Renovate-managed.

Default user is **root** (inherited from the base). Relay ports **2222** and
**8443** are unprivileged (> 1024) → **no `cap_net_bind_service` / `setcap`
needed**.

## Environment interface

The user-facing interface is namespaced `ASTRAVAULT_*`. `ASTRAVAULT_NET` picks
the networking role; the rest describe the astravault connection. The wrapper
translates internally (most → flags; a few → the CLI's own `INFISICAL_*` env).

### Common (both roles)

| Variable | Purpose |
|---|---|
| `ASTRAVAULT_NET` | **required**: `gateway` or `relay` |
| `ASTRAVAULT_DOMAIN` | astravault URL (e.g. `https://vault.astrateam.net`) |
| `ASTRAVAULT_ENROLL_METHOD` | `token` or `aws` |
| `ASTRAVAULT_TOKEN` | one-time enrollment token (**secret**) |
| `ASTRAVAULT_AUTH_METHOD` | machine-identity login instead of a token |
| `ASTRAVAULT_CLIENT_ID` / `ASTRAVAULT_CLIENT_SECRET` | universal-auth creds (**secret**) |

### Gateway only (`ASTRAVAULT_NET=gateway`)

| Variable | Purpose |
|---|---|
| `ASTRAVAULT_GATEWAY_NAME` | gateway name (`%h` → container hostname) |
| `ASTRAVAULT_TARGET_RELAY_NAME` | pin a relay; omit for auto-select + failover |
| `ASTRAVAULT_GATEWAY_ID` | gateway UUID (AWS enroll method) |
| `ASTRAVAULT_GATEWAY_ACCESS_TOKEN` | long-lived token → **stateless**, no disk (**secret**) |
| `ASTRAVAULT_PKCS11_MODULE` | absolute path to an HSM PKCS#11 driver |

### Relay only (`ASTRAVAULT_NET=relay`)

| Variable | Purpose |
|---|---|
| `ASTRAVAULT_RELAY_NAME` | relay name (`%h` → container hostname) |
| `ASTRAVAULT_RELAY_HOST` | static IP/DNS registered server-side |
| `ASTRAVAULT_RELAY_TYPE` | default `org` |
| `ASTRAVAULT_RELAY_ID` | relay UUID (AWS enroll method) |
| `ASTRAVAULT_RELAY_ACCESS_TOKEN` | long-lived token → **stateless**, no disk (**secret**) |
| `ASTRAVAULT_RELAY_AUTH_SECRET` | for `type=instance` (**secret**) |
| `ASTRAVAULT_RELAY_SSH_PORT` | healthcheck port (default `2222`) |

Any extra container args are forwarded to the subcommand (e.g. `--help`).

### Docker / Swarm secrets (`*_FILE`)

For any variable above, a `<VAR>_FILE` pointing at a mounted secret is read into
`<VAR>` (an explicit `<VAR>` wins over its `_FILE`).

## Ports

| Role | Publishes | Direction |
|---|---|---|
| **relay** | **2222** (gateways dial in) + **8443** (astravault platform dials in) | inbound |
| relay | 443 to astravault — **not published** | outbound |
| **gateway** | nothing (outbound-only) | — |

## Persistence — important

The **enrollment token is single-use** (1 h TTL). On first start the CLI
exchanges it for a long-lived access token and writes it to
`/etc/infisical/{gateways,relays}/<name>.conf` (root; `0600`). Two clean
patterns:

- **A. Persist a volume** at `/etc/infisical` → the access token survives
  restarts; re-running with the same enrollment token is a no-op.
- **B. Stateless** → supply `ASTRAVAULT_{GATEWAY,RELAY}_ACCESS_TOKEN` (or a
  machine identity via `ASTRAVAULT_AUTH_METHOD`); nothing is written to disk, so
  no volume is needed. Best fit for a rescheduled/replicated Swarm task.

## Health check

Built in (`HEALTHCHECK`), role-aware: **relay** → TCP connect to the SSH
listener (`2222`); **gateway** → process liveness (`pgrep infisical`, since it
has no local port).

## Examples — Docker Compose

Two ready-to-run, fully-commented compose files (every variable explained inline):

- **[examples/docker-compose.gateway.yml](examples/docker-compose.gateway.yml)** — a
  gateway next to your private resources (outbound-only, no published ports).
- **[examples/docker-compose.relay.yml](examples/docker-compose.relay.yml)** — a
  relay on a public host (publishes 2222 + 8443).

```bash
docker compose -f examples/docker-compose.gateway.yml up -d
docker compose -f examples/docker-compose.relay.yml   up -d
```

## Docker Swarm topology

Each **gateway is a distinct identity** (its config is scoped by name) and, with
the **token** method, each needs its **own single-use enrollment token**. That
rules out a single `mode: global` gateway service with the token method.

- **Recommended — pin one gateway per node** (`replicas: 1` each + a placement
  constraint), each with its own `ASTRAVAULT_GATEWAY_NAME` and token secret.
  Group them in an Infisical **Gateway Pool** for HA/routing.

  ```yaml
  # one stanza per node — gw-node01 / gw-node02 / gw-node03
  gateway-node01:
    image: ghcr.io/astrateam-net/astravaultnet:0.43.100
    environment:
      ASTRAVAULT_NET: gateway
      ASTRAVAULT_GATEWAY_NAME: gw-node01
      ASTRAVAULT_DOMAIN: https://vault.astrateam.net
      ASTRAVAULT_ENROLL_METHOD: token
      ASTRAVAULT_TOKEN_FILE: /run/secrets/gw_node01_token
    secrets: [gw_node01_token]
    deploy:
      replicas: 1
      placement:
        constraints: [node.hostname == node01]
  ```

- **Alternative — `mode: global` + machine-identity auth.** Global mode can't
  fan a single one-time token out to N tasks, so switch to a non-single-use
  credential (`ASTRAVAULT_AUTH_METHOD=universal-auth` + `ASTRAVAULT_CLIENT_ID`
  /`ASTRAVAULT_CLIENT_SECRET`, shared across tasks) and give each task a unique
  name via Swarm env templating: `ASTRAVAULT_GATEWAY_NAME={{.Node.Hostname}}`
  (or `%h` with `--hostname={{.Node.Hostname}}`). Every task self-authenticates
  on start, so no persistence is required.

**Relay** is not a good fit for global mode: it has a fixed server-side host
(static IP/DNS), so run it as a single pinned service (or one per public host
with distinct `ASTRAVAULT_RELAY_NAME` + `ASTRAVAULT_RELAY_HOST`).

## Local build & test

```bash
mise run local-build astravaultnet
```
