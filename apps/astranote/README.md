# astranote — deployment guide

`astranote` is a thin overlay on the upstream [`ghcr.io/toeverything/affine`](https://github.com/toeverything/AFFiNE)
image with the self-host **Team** tier unlocked at build time (see [`agent`](./agent) and
[`Dockerfile`](./Dockerfile)). Functionally it **is** AFFiNE — same runtime, same env vars, same
database schema — so upstream's [self-hosting docs](https://docs.affine.pro/self-host-affine)
apply verbatim. This guide only covers what the patch does and what a prod operator must provide.

> No licence key is required. Every self-hosted workspace resolves to the `selfhost_team`
> entitlement on its own.

---

## What the patch unlocks

AFFiNE's paid features all funnel through one resolver: `EntitlementService.resolveBestEntitlement()`,
whose `{ plan, quota, flags }` result is persisted into `effectiveWorkspaceQuotaState` and read by
the rest of the app (team-workspace features, member/storage/blob limits, permission policy). The
agent short-circuits that resolver so every self-hosted **workspace** resolves to an active
`selfhost_team` entitlement at maximum seats.

Stock vs patched (self-host):

| | plan | blob upload | storage | members |
|---|---|---|---|---|
| **stock** | `selfhost_free` | 100 MB | 100 GB | 10 |
| **astranote** | `selfhost_team` | 500 MB | effectively unlimited | 100 000 |

`selfhost_team` also flips `isTeamWorkspace`, which is what gates the Team-workspace feature set in
the permission layer.

### Why it needs no licence key

The real gate is native (Rust addon, `resolveEntitlementV1`). It **refuses** a commercial plan on
`deploymentType: "selfhosted"` unless handed a signed, key-verified licence blob — and the
verification keys are compiled into the `.node` binary, so they can't be swapped from outside. But
the **same** native resolver returns a full `selfhost_team` entitlement on `deploymentType: "cloud"`
— the exact path AFFiNE itself uses for remote-validated self-host licences. The agent routes every
self-hosted workspace through that path, so the quota/flags come out of the app's own resolver,
correct and verified — just without a licence. It never touches the native binary.

The agent does not hardcode any minified name; it extracts the resolver reference from `builtinFree`
(the app's canonical resolver call site) and asserts every anchor, so the **build fails loud** if
upstream moves a seam. Re-verify on every version bump.

---

## Scope: what this does NOT unlock

AI / Copilot metering (`unlimitedCopilot`) is a **separate** axis. It is gated on a per-user `ai`
entitlement, not the workspace plan, and the agent deliberately leaves it alone — because on
self-host it's already moot: **BYOK is free** (`ByokEntitlementPolicy` short-circuits
`if (env.selfhosted) return true`), so you bring your own OpenAI/Gemini/Anthropic key and Copilot
works without any entitlement. If you later want AFFiNE's *hosted* AI credits metered as unlimited,
that's a second patch on the user-quota reconcile — out of scope here.

---

## Secrets

AFFiNE reads config from environment variables (and an optional `config.json`). It has no `*_FILE`
convention and the agent does not add one — deliver secrets as plain env vars (or via your
orchestrator's env injection). The base image's `docker-entrypoint.sh` and
`CMD ["node", "./dist/main.js"]` are left untouched.

Minimum required env: `AFFINE_SERVER_HOST` (public host), a Postgres connection, and a Redis
connection. See upstream's [environment reference](https://docs.affine.pro/self-host-affine).

```yaml
# docker-compose.yml (Swarm) — abridged; see upstream for the full stack
services:
  astranote:
    image: ghcr.io/astrateam-net/astranote:rolling
    environment:
      AFFINE_SERVER_HOST: 'note.example.com'
      AFFINE_SERVER_HTTPS: 'true'
      DATABASE_URL: 'postgresql://affine:PASS@postgres:5432/affine'
      REDIS_SERVER_HOST: 'redis'
    depends_on: [postgres, redis]
    ports: ['3010:3010']

  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_USER: affine
      POSTGRES_PASSWORD: PASS
      POSTGRES_DB: affine
  redis:
    image: redis
```

Run migrations once before first boot with the same image:
`node ./scripts/self-host-predeploy.js`.

---

## Version pinning

`VERSION` in [`docker-bake.hcl`](./docker-bake.hcl) tracks `ghcr.io/toeverything/affine` (bare
semver tags, e.g. `0.27.1` = the `stable` release) via Renovate. Pin by digest in the deploy stack.
On every bump, confirm the build succeeded — the agent's asserted anchors are the canary; a silent
feature regression would show up as a workspace stuck on `selfhost_free`.
