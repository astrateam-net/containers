# containers

Custom container images for homelab and office infrastructure, published to `ghcr.io/astrateam-net`.

Images are built for `linux/amd64` and `linux/arm64`, versioned with semver tags, and updated automatically by Renovate.

---

## Images

| App | Image | Version |
|-----|-------|---------|
| [actions-runner](apps/actions-runner/) | `ghcr.io/astrateam-net/actions-runner` | `2.333.0` |
| [actions-runner-synology](apps/actions-runner-synology/) | `ghcr.io/astrateam-net/actions-runner-synology` | `0.1.0` |
| [agile](apps/agile/) | `ghcr.io/astrateam-net/agile` | `11.3.3` |
| [atuin-server-sqlite](apps/atuin-server-sqlite/) | `ghcr.io/astrateam-net/atuin-server-sqlite` | `v18.4.0` |
| [cloudflared](apps/cloudflared/) | `ghcr.io/astrateam-net/cloudflared` | `2026.3.0` |
| [flowise](apps/flowise/) | `ghcr.io/astrateam-net/flowise` | `3.1.1` |
| [flowise-worker](apps/flowise-worker/) | `ghcr.io/astrateam-net/flowise-worker` | `3.1.1` |
| [ghost](apps/ghost/) | `ghcr.io/astrateam-net/ghost` | `6.21.0` |
| [gotenberg](apps/gotenberg/) | `ghcr.io/astrateam-net/gotenberg` | `8.27.0` |
| [home-assistant](apps/home-assistant/) | `ghcr.io/astrateam-net/home-assistant` | `2025.11.3` |
| [k8s-sidecar](apps/k8s-sidecar/) | `ghcr.io/astrateam-net/k8s-sidecar` | `2.5.0` |
| [minio-browser](apps/minio-browser/) | `ghcr.io/astrateam-net/minio-browser` | `v1.7.6` |
| [nocodb](apps/nocodb/) | `ghcr.io/astrateam-net/nocodb` | `0.301.5` |
| [paperless-ngx](apps/paperless-ngx/) | `ghcr.io/astrateam-net/paperless-ngx` | `2.20.13` |
| [penpot-mcp](apps/penpot-mcp/) | `ghcr.io/astrateam-net/penpot-mcp` | `0.0.1` |
| [postgres-pgbackrest](apps/postgres-pgbackrest/) | `ghcr.io/astrateam-net/postgres-pgbackrest` | `17.8.0` |
| [rest-api-redis](apps/rest-api-redis/) | `ghcr.io/astrateam-net/rest-api-redis` | `1.0.7` |
| [sunsama-api](apps/sunsama-api/) | `ghcr.io/astrateam-net/sunsama-api` | `1.0.0` |
| [tana](apps/tana/) | `ghcr.io/astrateam-net/tana` | `1.515.0` |
| [vlmcsd](apps/vlmcsd/) | `ghcr.io/astrateam-net/vlmcsd` | `svn1113` |
| [webstudio](apps/webstudio/) | `ghcr.io/astrateam-net/webstudio` | `0.235.0` |
| [wiki](apps/wiki/) | `ghcr.io/astrateam-net/wiki` | `10.2.7` |

---

## Using Images

### Tags

Each image is published with the following tags:

| Tag | Example | Mutable |
|-----|---------|---------|
| Full version | `2.332.0` | No |
| Minor version | `2.332` | Yes |
| Major version | `2` | Yes |
| Rolling | `rolling` | Yes |

Pin to a `sha256` digest for true immutability:

```sh
docker pull ghcr.io/astrateam-net/actions-runner:2.332.0@sha256:<digest>
```

### Verify Attestation

Images are signed with GitHub's [attest-build-provenance](https://github.com/actions/attest-build-provenance). Verify with:

```sh
gh attestation verify --repo astrateam-net/containers \
  oci://ghcr.io/astrateam-net/<app>:<tag>
```

---

## Adding an App

1. Create `apps/<name>/` with these files:

   ```
   apps/<name>/
   ├── Dockerfile
   ├── docker-bake.hcl
   └── tests.yaml
   ```

2. **`docker-bake.hcl`** — follow the standard pattern:

   ```hcl
   target "docker-metadata-action" {}

   variable "VERSION" {
     // renovate: datasource=docker depName=<upstream-image>
     default = "1.2.3"
   }

   variable "SOURCE" {
     default = "https://github.com/upstream/repo"
   }

   group "default" {
     targets = ["image-local"]
   }

   target "image" {
     inherits = ["docker-metadata-action"]
     args = { VERSION = "${VERSION}" }
     labels = { "org.opencontainers.image.source" = "${SOURCE}" }
   }

   target "image-local" {
     inherits = ["image"]
     output = ["type=docker"]
   }

   target "image-all" {
     inherits = ["image"]
     platforms = ["linux/amd64", "linux/arm64"]
   }
   ```

3. **`tests.yaml`** — use [GOSS](https://github.com/goss-org/goss) format (default) or [Container Structure Test](https://github.com/GoogleContainerTools/container-structure-test) format (requires `schemaVersion` key). The Taskfile auto-detects which to use.

4. **Renovate** — the `// renovate: datasource=...` comment in `docker-bake.hcl` enables automatic version updates. See [Renovate docs](https://docs.renovatebot.com/modules/datasource/) for datasource options.

5. Push to `main` — the Release workflow triggers automatically on changes to `apps/**`.

---

## Local Development

```sh
# Install test tools (goss/dgoss)
task init

# Build and test locally
task local-build-<app-name>

# Trigger remote build via GitHub Actions (no release)
task remote-build-<app-name>

# Trigger remote build + publish release
task remote-build-<app-name> RELEASE=true
```

**Prerequisites:** `docker`, `gh`, `jq`, `yq`, `container-structure-test` (for CST apps)
