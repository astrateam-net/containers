# pangolin

`ghcr.io/astrateam-net/pangolin` — [Pangolin](https://github.com/fosrl/pangolin) **Enterprise
(postgresql)**, rebuilt from a pinned upstream tag with a small patch series that makes exit-node
**subdomains deterministic** instead of random.

The build mirrors upstream's own packaging (`BUILD=enterprise`, `DATABASE=pg`, same Next.js +
esbuild pipeline), so the result matches the published `fosrl/pangolin:ee-postgresql-<VERSION>`
image outside the two patched functions.

> **License:** `server/private/**` is Fossorial's proprietary Enterprise source. This image is
> built and run under our own Enterprise license; treat the image accordingly.

## Why a fork

With `use_subdomain: true`, stock Pangolin gives each exit node a **random** `adjective-animal`
label ([`server/db/names.ts`](https://github.com/fosrl/pangolin) `getUniqueExitNodeEndpointName`),
generated only *after* the gerbil registers. You cannot pre-create a DNS record for a name you
don't know yet — which is exactly why upstream pairs random labels with a **dynamic authoritative
DNS** component (Pangolin DNS on :53 + NS delegation).

We don't run that component. Our exit nodes have **static, operator-chosen names** (one Swarm
service per node — see [`gerbil-traefik-s6`](../gerbil-traefik-s6/)), so we want the exit-node
endpoint to be a name we already know and can pre-create in DNS ourselves.

| | Stock EE (`use_subdomain: true`) | This fork |
|---|---|---|
| Exit-node label | random `swift-otter` (post-registration) | deterministic, from the gerbil's `reachableAt` host |
| Endpoint | `swift-otter.wg.example.net` | `png01.wg.example.net` |
| DNS record | needs Pangolin dynamic DNS / NS delegation | **you pre-create a static A record** |

## What the patch does

Two files, applied with `git apply` at build time (fails the build loudly on any upstream drift
from `VERSION`). Full analysis: [`docs/pangolin-exit-node-subdomains.md`](../../../../../Gitlab/astrateam-net/Infra/net/tower/docs/pangolin-exit-node-subdomains.md).

| Patch | File | Change |
|-------|------|--------|
| [`0001`](patches/0001-deterministic-exit-node-subdomain.patch) | `server/private/routers/gerbil/createExitNode.ts` (EE) | When `use_subdomain` is on, `subEndpoint` = the first host label of the gerbil's `reachableAt` (`http://png01:3004` → `png01`), lower-cased and DNS-sanitized. Falls back to the upstream random name if `reachableAt` is missing/unparseable. |
| [`0002`](patches/0002-preserve-subdomain-endpoints-on-boot.patch) | `server/setup/copyInConfig.ts` | `copyInConfig` runs on **every** server start (`server/index.ts:37` → `runSetupFunctions` → `copyInConfig`) and resets any endpoint `!= base_endpoint` back to `base_endpoint`. With `use_subdomain` on, that reset is skipped so the `png0N` labels survive restarts (`listenPort` is still normalized). |

**No gerbil fork needed.** The gerbil already reports `reachableAt`; the label is derived from it,
so the identity anchor is the gerbil's stable WireGuard public key and the name is stable per node.

## How to use it

1. Set in Pangolin `config.yml`:
   ```yaml
   gerbil:
     use_subdomain: true
     base_endpoint: wg.example.net       # always the suffix
     # exit_node_name: unset in HA (a single shared name collapses all nodes)
   ```
2. Name each gerbil service = the public label you want, and set `REACHABLE_AT` to match:
   `REACHABLE_AT=http://png01:3004` ⇒ endpoint `png01.wg.example.net`.
3. **Pre-create the DNS** yourself: `png01.wg.example.net A <tower01 public IP>`, etc.
   No dynamic authoritative DNS required.

## Build

Four-stage [`Dockerfile`](Dockerfile): fetch upstream source at `${VERSION}` → `git apply patches/`
→ `set:enterprise` + `set:pg` + full build → assemble runner (mirrors upstream's runner stage;
context COPYs are pulled from the in-image source, not the build context).

### Version (single `docker-bake.hcl` variable, Renovate-tracked)

| Variable | Tracks | Datasource | Default |
|---|---|---|---|
| `VERSION` | upstream Pangolin release | `github-releases` → `fosrl/pangolin` | `1.19.4` |

```bash
mise run local-build pangolin     # build + container-structure-test
```

## Deploy

Drop-in for `fosrl/pangolin:ee-postgresql-<VERSION>` — same runtime contract (Postgres + Valkey,
`/app/config`, ports 3000/3001/3002/3003, `npm run start` runs migrations then the server). The
only behavioural difference is exit-node endpoint naming, gated behind `use_subdomain: true`; with
`use_subdomain: false` it is byte-for-byte upstream behaviour.
