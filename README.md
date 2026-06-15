# containers

Custom container images for homelab and office infrastructure, published to `ghcr.io/astrateam-net`.

Images are built for `linux/amd64` and `linux/arm64`, versioned with semver tags, and updated automatically by Renovate.

---

## Images

| App | Image | Version |
|-----|-------|---------|
| [astrapdf](apps/astrapdf/) | `ghcr.io/astrateam-net/astrapdf` | `2.11.0` |
| [authentik](apps/authentik/) | `ghcr.io/astrateam-net/authentik` | `2026.5.3` |
| [bird-maxmind](apps/bird-maxmind/) | `ghcr.io/astrateam-net/bird-maxmind` | `0.1.2` |
| [bkm](apps/bkm/) | `ghcr.io/astrateam-net/bkm` | `10.2.11` |
| [bpm](apps/bpm/) | `ghcr.io/astrateam-net/bpm` | `11.3.6` |
| [ci-ansible](apps/ci-ansible/) | `ghcr.io/astrateam-net/ci-ansible` | `1.1.0` |
| [ci-opentofu](apps/ci-opentofu/) | `ghcr.io/astrateam-net/ci-opentofu` | `1.1.0` |
| [dev](apps/dev/) | `ghcr.io/astrateam-net/dev` | `v2.34.1` |
| [dev-gw](apps/dev-gw/) | `ghcr.io/astrateam-net/dev-gw` | `2026.2.2` |
| [gh-actions-runner](apps/gh-actions-runner/) | `ghcr.io/astrateam-net/gh-actions-runner` | `0.3.0` |
| [gotenberg](apps/gotenberg/) | `ghcr.io/astrateam-net/gotenberg` | `8.30.1` |
| [n8n-mcp](apps/n8n-mcp/) | `ghcr.io/astrateam-net/n8n-mcp` | `2.47.12` |
| [newt-swarm](apps/newt-swarm/) | `ghcr.io/astrateam-net/newt-swarm` | `1.13.0` |
| [obsync](apps/obsync/) | `ghcr.io/astrateam-net/obsync` | `3.5.1` |
| [postgres-pgbackrest](apps/postgres-pgbackrest/) | `ghcr.io/astrateam-net/postgres-pgbackrest` | `17.8.0` |
| [postiz](apps/postiz/) | `ghcr.io/astrateam-net/postiz` | `v2.21.8` |
| [vlmcsd](apps/vlmcsd/) | `ghcr.io/astrateam-net/vlmcsd` | `svn1113` |
| [xtrabackup](apps/xtrabackup/) | `ghcr.io/astrateam-net/xtrabackup` | `8.4.0-2` |

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
