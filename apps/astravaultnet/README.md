# astravaultnet

Infisical **Networking** (gateway, relay *or* agent proxy) packaged as a single,
env-driven container image. Thin wrapper over the official [`infisical/cli`](https://hub.docker.com/r/infisical/cli)
image — all three roles are subcommands of that one binary. It adds an
entrypoint that dispatches on one variable, resolves Docker / Swarm secrets, and
maps a clean env interface onto the CLI flags that have no env of their own.

One container runs **one role**, selected by
`ASTRAVAULT_NET=gateway|relay|agent-proxy`.

```
gateway  ──outbound SSH tunnel──▶  relay  ──▶  Infisical platform (astravault)
(near your resources)              (public host, static IP/DNS)

agent    ──HTTPS_PROXY──▶  agent proxy  ──credentials injected──▶  external APIs
(coding agent host)        (its own host)
```

**gateway / relay** let astravault reach *into* your private network. The
**agent proxy** points the other way: agents route their outbound HTTP(S)
through it, and it injects the real credentials on the wire, so an agent calls
authenticated APIs while never holding the secret.

## Base image / building blocks

`FROM infisical/cli:<version>` — the leanest available block: Alpine + `tini`
+ the statically linked `infisical` binary, published multi-arch (amd64/arm64)
by Infisical. `VERSION` in `docker-bake.hcl` tracks the CLI release and is
Renovate-managed.

Each role is its own long-running foreground process, so running more than one
in a container needs a supervisor: **s6-overlay** (PID 1 via `/init`) runs one
longrun per role, and a role absent from `ASTRAVAULT_NET` takes itself down at
start rather than flapping. Everything else is POSIX shell over busybox.

Default user is **root** (inherited from the base). Every listening port —
relay **2222**/**8443**, agent proxy **17322** — is unprivileged (> 1024) →
**no `cap_net_bind_service` / `setcap` needed**.

## Environment interface

The user-facing interface is namespaced `ASTRAVAULT_*`. `ASTRAVAULT_NET` picks
the roles; the rest describe the astravault connection. The wrapper translates
internally (most → flags; a few → the CLI's own `INFISICAL_*` env).

### Common (all roles)

| Variable | Purpose |
|---|---|
| `ASTRAVAULT_NET` | **required**: `gateway`, `relay`, `agent-proxy` — or a list |
| `ASTRAVAULT_DOMAIN` | astravault URL (e.g. `https://vault.astrateam.net`) |
| `ASTRAVAULT_ENROLL_METHOD` | `token` or `aws` |
| `ASTRAVAULT_TOKEN` | one-time enrollment token (**secret**) |
| `ASTRAVAULT_AUTH_METHOD` | machine-identity login instead of a token |
| `ASTRAVAULT_CLIENT_ID` / `ASTRAVAULT_CLIENT_SECRET` | universal-auth creds (**secret**) |

Each of these also takes a **role-scoped** form that wins over the shared one —
`ASTRAVAULT_GATEWAY_*`, `ASTRAVAULT_RELAY_*`, `ASTRAVAULT_PROXY_*`. So roles
sharing one identity set `ASTRAVAULT_CLIENT_ID` once; roles needing separate
identities set `ASTRAVAULT_GATEWAY_CLIENT_ID` and `ASTRAVAULT_PROXY_CLIENT_ID`
instead. Same for `DOMAIN`, `ENROLL_METHOD`, `TOKEN` and `AUTH_METHOD`.

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

### Agent proxy only (`ASTRAVAULT_NET=agent-proxy`)

Authenticates with a **machine identity** — `ASTRAVAULT_PROXY_CLIENT_ID` +
`ASTRAVAULT_PROXY_CLIENT_SECRET` (or the shared `ASTRAVAULT_CLIENT_ID` /
`ASTRAVAULT_CLIENT_SECRET`) are **required** and are its only credential source.
They are handed to the CLI through its own environment, never as flags, so they
never appear in `ps`.

| Variable | Purpose |
|---|---|
| `ASTRAVAULT_PROXY_PORT` | listen port (default `17322`); also the healthcheck port |
| `ASTRAVAULT_PROXY_UNMATCHED_HOST` | `allow` (default) or `block` — what to do with hosts no proxied service matches |
| `ASTRAVAULT_PROXY_POLL_INTERVAL` | seconds between permission/credential refreshes (default `60`) |
| `ASTRAVAULT_PROXY_LOG_FORMAT` | `console` (default) or `json` |
| `ASTRAVAULT_PROXY_LOG_FILE` | additionally write JSON logs to this path |
| `ASTRAVAULT_PROXY_LOG_LEVEL` | doubles as the activity filter: `debug` also logs passthrough, `info` (default) logs brokered, `warn` only blocked/errors |

`block` rejects **every** unmatched host including astravault itself, so an
agent's own `infisical` calls stop working — use it only for a strict allowlist.

### Docker / Swarm secrets (`*_FILE`)

For any variable above, a `<VAR>_FILE` pointing at a mounted secret is read into
`<VAR>` (an explicit `<VAR>` wins over its `_FILE`).

## Running several roles at once

`ASTRAVAULT_NET` takes a list — `gateway,agent-proxy` — and each named role gets
its own supervised process. The ports never collide, so any combination is
valid. The natural pairing is a **node-pinned gateway that doubles as one of the
agent proxy replicas**: gateways are already one-per-node with their own name
and enrollment token, and the agent proxy is stateless, so the same three nodes
give you three proxies behind an L4 load balancer.

```yaml
environment:
  ASTRAVAULT_NET: gateway,agent-proxy
  ASTRAVAULT_DOMAIN: https://vlt.astrateam.net
  # gateway: its own identity, per node
  ASTRAVAULT_GATEWAY_NAME: ivn-sw-gw-01
  ASTRAVAULT_ENROLL_METHOD: token
  ASTRAVAULT_TOKEN_FILE: /run/secrets/astravault_gw_enroll_token_sw01
  # agent proxy: a machine identity of its own
  ASTRAVAULT_PROXY_CLIENT_ID_FILE: /run/secrets/astravault_proxy_client_id
  ASTRAVAULT_PROXY_CLIENT_SECRET_FILE: /run/secrets/astravault_proxy_client_secret
```

The container is healthy only when **every** selected role is up, so a crashed
gateway marks the task unhealthy and restarts the proxy with it. Split them into
two services if you want independent restarts.

## Ports

| Role | Publishes | Direction |
|---|---|---|
| **relay** | **2222** (gateways dial in) + **8443** (astravault platform dials in) | inbound |
| relay | 443 to astravault — **not published** | outbound |
| **agent proxy** | **17322** (agents point `HTTPS_PROXY` here) | inbound |
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

The **agent proxy is stateless by construction** — it holds its cache, leases
and signed intermediate in memory and writes nothing, so replicas need no volume
and no shared database. They coordinate through astravault itself: each signs
its own intermediate under the same org root CA, so an agent trusts any of them,
and each polls independently (a rotated secret propagates within one
`ASTRAVAULT_PROXY_POLL_INTERVAL`).

## Health check

Built in (`HEALTHCHECK`): healthy only when **every** role named in
`ASTRAVAULT_NET` is supervised-up, plus a TCP connect for the roles that listen
— **relay** on `2222`, **agent proxy** on `17322`. The **gateway** is
outbound-only and has no port, so supervision is the signal.

## Examples — Docker Compose

Ready-to-run, fully-commented compose files (every variable explained inline):

- **[examples/docker-compose.gateway.yml](examples/docker-compose.gateway.yml)** — a
  gateway next to your private resources (outbound-only, no published ports).
- **[examples/docker-compose.relay.yml](examples/docker-compose.relay.yml)** — a
  relay on a public host (publishes 2222 + 8443).
- **[examples/docker-compose.agent-proxy.yml](examples/docker-compose.agent-proxy.yml)** — an
  agent proxy on its own host (publishes 17322), plus the combined
  gateway + agent-proxy variant.

```bash
docker compose -f examples/docker-compose.gateway.yml     up -d
docker compose -f examples/docker-compose.relay.yml       up -d
docker compose -f examples/docker-compose.agent-proxy.yml up -d
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

**Agent proxy** is the opposite case — every replica is identical and stateless,
so plain `replicas: N` (or `mode: global`) works with one shared machine
identity and no volume. Two ways to place it:

- **Its own service**, published on 17322 to the agent network. Independent
  restarts and independent scaling.
- **Folded into the node-pinned gateways** via `ASTRAVAULT_NET: gateway,agent-proxy`.
  Since the gateways are already one per node, that gives one proxy per node for
  free — at the cost of shared health between the two roles.

## Local build & test

```bash
mise run local-build astravaultnet
```
