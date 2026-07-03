# gerbil-traefik-s6

`ghcr.io/astrateam-net/gerbil-traefik-s6` — [Gerbil](https://github.com/fosrl/gerbil)
and [Traefik](https://github.com/traefik/traefik) in a single
[s6-overlay](https://github.com/just-containers/s6-overlay)-supervised image, so
the two processes share one network namespace.

This is a packaging image, not a fork: both programs are the stock upstream
binaries (Gerbil's own image as the base, Traefik's binary lifted from the
official image). Nothing about their behaviour is patched — only how they are
co-located.

## Why this exists

Pangolin's reference topology runs Traefik with `network_mode: service:gerbil`.
Traefik has to live **inside Gerbil's network namespace** because:

- Gerbil creates the WireGuard `wg0` interface and owns the public ports.
- Traefik's upstreams for tunnelled resources are IPs that **only exist on
  `wg0`**. From any other namespace they are unreachable.

`network_mode: service:gerbil` puts Traefik's whole network stack inside
Gerbil's container to make that work.

**Docker Swarm has no `network_mode: service:` equivalent** — it assumes tasks
may land on different nodes, so it never added the "share another container's
namespace" primitive. The only way to preserve the shared namespace in Swarm is
to run both processes in **one** container. That is this image.

| | Reference stack (Compose) | This image (Swarm-friendly) |
|---|---|---|
| Gerbil | own container | process in this container |
| Traefik | `network_mode: service:gerbil` | process in this container (same netns, for free) |
| Shared `wg0` | via `network_mode` | via being one container |
| Pangolin | separate container | **unchanged — still separate** |

### Why Pangolin is NOT in here

Pangolin talks to Gerbil and Traefik over HTTP by DNS name
(`http://pangolin:3001`), never through the shared network stack. It has no
reason to join the namespace, and folding it in would only couple an
independently-deployed, stateful service to this one. So the merge is the
**minimal** forced pair — Gerbil + Traefik — and nothing more. Because Pangolin
stays external, the Traefik/Gerbil configs keep their `pangolin:*` DNS names
unchanged (no `localhost` rewrite).

## How it works

s6-overlay is PID 1 (`ENTRYPOINT ["/init"]`) and supervises two `longrun`
services under [`rootfs/etc/s6-overlay/s6-rc.d/`](rootfs/etc/s6-overlay/s6-rc.d/):

| Service | Command | Notes |
|---|---|---|
| `gerbil` | `gerbil` (no flags) | Creates `wg0`, pulls peer config from Pangolin. Configured purely by its own env vars (see below); the three essentials have defaults baked as `ENV` in the Dockerfile. |
| `traefik` | `traefik --configFile=/etc/traefik/traefik_config.yml` | Config is **mounted**, not baked. Inherits env (e.g. `CLOUDFLARE_DNS_API_TOKEN`) via `with-contenv`. |

The two are **independent siblings** — no `dependencies` between them. Neither
talks to the other directly; they only need the shared netns so Traefik's
`:80/:443` land where `wg0` lives. Both simply retry until the external Pangolin
answers, so no readiness gate is needed. If either dies, s6 restarts just that
one. The `HEALTHCHECK` ([`healthcheck.sh`](rootfs/usr/bin/healthcheck.sh)) is
green only when **both** report `up`.

## Configuration: where the two services' settings go

In the reference stack Gerbil and Traefik are two service definitions, each with
its own `command` / `environment` / `ports` / `volumes`. Merged into one
container they become **one** service definition that is the union of both.
There is no per-process split to declare — a container's env is one flat
namespace, and each program reads only the variable names it recognises. Gerbil's
names and Traefik's names don't overlap, so you list them together.

| Reference-stack field | Where it goes here |
|---|---|
| Gerbil `command:` flags (`--remoteConfig`, `--reachableAt`, `--generateAndSaveKeyTo`) | **Gone** — folded into Gerbil's env vars, defaulted as `ENV` in the image (`REMOTE_CONFIG`, `REACHABLE_AT`, `GENERATE_AND_SAVE_KEY_TO`). Override via env only if names differ. |
| Traefik `command:` (`--configFile=…`) | **Baked** into the `traefik` run script. |
| Gerbil options (MTU, log level, SNI port, proxy-protocol, …) | Its documented env vars (`MTU`, `LOG_LEVEL`, `SNI_PORT`, `PROXY_PROTOCOL`, `INTERFACE`, …) on the one `environment:`. Precedence is **env > flag > default**. |
| Traefik `environment:` (`CLOUDFLARE_DNS_API_TOKEN`, `DOMAIN_AT`, …) | The **same** `environment:` block — different names, no collision. |
| Traefik routers / services / entrypoints / certresolvers / plugins / middlewares | **Unchanged** — these were never env vars. They live in the mounted files `/etc/traefik/traefik_config.yml`, `dynamic_config.yml`, `rules/`. |
| Gerbil `ports:` (80, 443, 51820/udp, 21820/udp) | On the one service. (They were on Gerbil originally precisely because Traefik shared its netns.) |
| Gerbil volume `/var/config` + Traefik volumes (`/etc/traefik`, `letsencrypt`, `logs`, `rules`) | All on the one service. |
| Gerbil `cap_add: [NET_ADMIN, SYS_MODULE]` | On the one service. |
| Traefik `network_mode: service:gerbil` | **Deleted** — that coupling is the whole reason this image exists. |

The full merged service block is under [Deploy](#deploy).

## Build

Two-stage [`Dockerfile`](Dockerfile):

1. `FROM traefik:${TRAEFIK_VERSION}` — source of the static, CGO-free Traefik
   binary.
2. `FROM ghcr.io/fosrl/gerbil:${VERSION}` (Alpine, already ships
   `iptables`/`iproute2`) — the runtime. Copies in the Traefik binary, installs
   s6-overlay (arch-mapped from `TARGETARCH` for amd64/arm64), lays down
   `rootfs/`.

No Node runtime — Pangolin is external.

### Versions (all `docker-bake.hcl` variables, Renovate-tracked)

| Variable | Tracks | Datasource | Default |
|---|---|---|---|
| `VERSION` | Gerbil (also the image tag) | `docker` → `ghcr.io/fosrl/gerbil` | `1.4.2` |
| `TRAEFIK_VERSION` | Traefik binary | `docker` → `traefik` | `v3.6.22` |
| `S6_OVERLAY_VERSION` | s6-overlay | `github-releases` → `just-containers/s6-overlay` | `3.2.3.0` |

Traefik is pinned to the **3.6 line** to match the proven standalone
`traefik_config.yml` (badger plugin, entrypoints); a jump to 3.7.x should be a
deliberate, separate change. Each version is overridable ad-hoc
(`TRAEFIK_VERSION=v3.7.6 docker buildx bake …`) — the same mechanism Renovate
uses when it edits the `default = "…"` line.

```bash
mise run local-build gerbil-traefik-s6   # build + container-structure-test
```

## Deploy

Collapse the reference stack's two services into one. The block below is the
union of the reference `gerbil` + `traefik` definitions on this image — no
`command:` (Gerbil flags became env defaults, Traefik's `--configFile` is baked)
and no `network_mode:`:

```yaml
services:
  gerbil:                                    # keep this name (DNS: gerbil:3004, gerbil:8080)
    image: ghcr.io/astrateam-net/gerbil-traefik-s6:<tag>
    restart: unless-stopped
    cap_add: [NET_ADMIN, SYS_MODULE]         # for wg0
    ports:                                   # Gerbil's + Traefik's 80/443 all land here
      - 51820:51820/udp
      - 21820:21820/udp
      - 443:443
      - 80:80
    environment:                             # one flat block; names don't collide
      - CLOUDFLARE_DNS_API_TOKEN=${CLOUDFLARE_DNS_API_TOKEN}   # Traefik
      - DOMAIN_AT=${DOMAIN_AT}                                 # Traefik
      # Gerbil defaults are baked; uncomment only to override, e.g.:
      # - REMOTE_CONFIG=http://pangolin:3001/api/v1/
      # - LOG_LEVEL=DEBUG
    volumes:
      - /data/tower/stacks/pangolin/gerbil:/var/config             # Gerbil wg key
      - /data/tower/stacks/pangolin/traefik:/etc/traefik:ro        # Traefik config
      - /data/tower/stacks/pangolin/traefik/letsencrypt:/letsencrypt
      - /data/tower/stacks/pangolin/traefik/logs:/var/log/traefik
      - /data/tower/stacks/pangolin/traefik/rules:/rules
    # no command:  — folded into the image
    # no network_mode: — the whole point of the merge
```

Everything else in the stack — `pangolin`, `crowdsec`, `middleware-manager`,
`geoipupdate`, the Traefik-log dashboards — stays **exactly** as-is, talking by
DNS name (`middleware-manager` still reaches Traefik's API at `gerbil:8080`).

## Local testing (hand-off notes)

> For whoever brings this up on a single-node Swarm to verify it. Everything
> needed is in this folder.

Build (or use the already-built local image):

```bash
mise run local-build gerbil-traefik-s6     # builds + runs container-structure-test
docker tag <fresh-image-id> gerbil-traefik-s6:local
```

The `:local` tag does **not** auto-update: `docker buildx bake --load` loads each
build as a dangling `<none>` image, so after any rebuild re-tag the newest one
(`docker images -a`, pick the freshest by `CreatedAt`) as `gerbil-traefik-s6:local`.

### What this image expects at runtime

It is **only** Gerbil + Traefik. To see it actually work you must provide the
two things it deliberately does not carry:

1. **A reachable Pangolin** at `pangolin:3001` (same network). Without it Gerbil
   loops on "fetching remote config" and Traefik's HTTP provider has nothing to
   read. Either run `fosrl/pangolin` alongside, or point
   `GERBIL_REMOTE_CONFIG` at a real one.
2. **A Traefik config mounted at `/etc/traefik`** (`traefik_config.yml` +
   `dynamic_config.yml`, and a `letsencrypt` dir). The image does not bake it.

### Minimal stack to bring it up

```yaml
services:
  gerbil:                              # service name MUST be `gerbil`
    image: gerbil-traefik-s6:local
    cap_add: [NET_ADMIN, SYS_MODULE]   # for wg0
    ports:
      - 80:80
      - 443:443
      - 51820:51820/udp
      - 21820:21820/udp
    volumes:
      - ./config/traefik:/etc/traefik  # traefik_config.yml + dynamic_config.yml + letsencrypt/
      - ./config/gerbil:/var/config    # wg key is generated here
    environment:
      - CLOUDFLARE_DNS_API_TOKEN=...    # if the traefik config uses the CF DNS challenge
      # override defaults only if names differ:
      # - GERBIL_REMOTE_CONFIG=http://pangolin:3001/api/v1/
      # - GERBIL_REACHABLE_AT=http://gerbil:3004

  pangolin:                            # the external brain — separate service, unchanged
    image: fosrl/pangolin:latest
    volumes:
      - ./config/pangolin:/app/config
```

### How to verify it is doing the right thing

- **Both processes up:** `docker ps` shows the container `healthy` (the
  healthcheck is green only when `s6-svstat` reports both `gerbil` and `traefik`
  as `up`).
- **Shared network namespace (the whole point):** inside the *one* container you
  should see both Gerbil's `wg0` and Traefik's listeners:
  ```bash
  docker exec gerbil ip addr            # wg0 present
  docker exec gerbil ss -tlnp           # :80 and :443 held by traefik, in the same netns as wg0
  ```
- **s6 supervision:** `docker logs gerbil` shows
  `s6-rc: info: service gerbil successfully started` and
  `... service traefik successfully started`. Kill one process and s6 restarts
  just it (the other keeps running).
- **Expected failure when Pangolin is absent:** Gerbil logs
  `Error fetching remote config … lookup pangolin: no such host`. That is the
  signal the external dependency is missing, not an image defect.
