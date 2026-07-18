# astranote — deployment guide

`astranote` is a thin overlay on the upstream
[`ghcr.io/toeverything/affine`](https://github.com/toeverything/AFFiNE) image. Functionally it
**is** AFFiNE — same runtime, same env vars, same database schema — so upstream's
[self-hosting docs](https://docs.affine.pro/self-host-affine) apply verbatim. This guide only
covers what a prod operator must provide.

## Secrets

AFFiNE reads config from environment variables (and an optional `config.json`). It has no `*_FILE`
convention — deliver secrets as plain env vars (or via your orchestrator's env injection). The base
image's `docker-entrypoint.sh` and `CMD ["node", "./dist/main.js"]` are left untouched.

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

## Version pinning

`VERSION` in [`docker-bake.hcl`](./docker-bake.hcl) tracks `ghcr.io/toeverything/affine` (bare
semver tags, e.g. `0.27.1` = the `stable` release) via Renovate. Pin by digest in the deploy stack.
Confirm the build succeeded on every bump.
