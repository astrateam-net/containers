# netbox

Official [netbox-docker](https://github.com/netbox-community/netbox-docker) image + the two plugins
carried from the old homelab deploy + `boto3` for Cloudflare R2 media. Published as
`ghcr.io/astrateam-net/netbox`. Consumed by the **tower** repo (`stacks/tools/netbox`).

## What this adds to the base

- **netbox-acls** — access-list modelling.
- **netboxlabs-diode-netbox-plugin** — write-side API for the **Diode ingestion / NetBox Discovery**
  pipeline (adds `/api/plugins/diode` + the *Diode → Client Credentials* UI). Runs on **safe
  defaults** (`diode_target = grpc://localhost:8080/diode`, no secret) with **no required settings**,
  so NetBox boots fine before the Diode server exists — the UI just sits idle. The real gRPC target
  and `netbox_to_diode` secret are environment-specific and belong in the **tower** stack's runtime
  `config/extra.py` (`PLUGINS_CONFIG`), added when the Diode server is deployed — not baked here.
  Ships a migration; the `app` service's entrypoint auto-applies it on boot.
- **netboxlabs-netbox-branching** — git-like branching. **Must be last in `PLUGINS`**; needs
  `DATABASES` wrapped in `DynamicSchemaDict` + a router. `configuration/plugins.py` imports the
  env-built `DATABASES` from netbox-docker's `configuration.py` and wraps it, so **no DB password is
  hardcoded** (unlike the upstream branching-on-docker guide).
- **boto3** — the AWS SDK the base image doesn't ship; required by django-storages for R2.

`collectstatic` runs at build so the plugins' static assets are baked in. The `SECRET_KEY` used for
that step is a throwaway — build-time only, never used at runtime (the real key is a Docker secret).

## Dropped in the 4.6 move

| Plugin | Reason |
|---|---|
| `nextbox-ui-plugin` | No NetBox 4.6 release (newest, 1.0.7, tops out at 4.1). |
| `netbox-routing` | Already disabled on the old host; unused. |

## Versions

All pinned in [`docker-bake.hcl`](docker-bake.hcl) (renovate-tracked):

| Variable | Purpose |
|---|---|
| `VERSION` | NetBox app version → our published image tag |
| `NETBOX_DOCKER_VERSION` | netbox-docker packaging version; base tag = `v${VERSION}-${NETBOX_DOCKER_VERSION}` |
| `NETBOX_ACLS_VERSION` / `NETBOX_DIODE_VERSION` / `NETBOX_BRANCHING_VERSION` | plugin pins (keep NetBox-4.6-compatible; Diode ≥ 1.12.0 for 4.6) |

## Build

```bash
docker buildx bake image-local          # local single-arch
docker buildx bake image-all            # multi-arch (CI)
```

CI (`.github/workflows/app-builder.yaml`) builds + pushes on release. Structural checks in
[`tests.yaml`](tests.yaml).
