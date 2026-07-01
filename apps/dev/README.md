# dev

`ghcr.io/astrateam-net/dev` — a custom build of [Coder](https://github.com/coder/coder),
rebuilt from a pinned upstream tag with a local patch series applied on top.

The build mirrors upstream's own pipeline (`scripts/build_go.sh` + the
`build-slim` Makefile packaging), so the result matches the published image
byte-for-byte outside `/opt/coder` — same `terraform`, entrypoint, and non-root
uid 1000 user from the upstream runtime base.

## Why a custom build

| Change | Where | What it does |
|--------|-------|--------------|
| Privileged port bind | Stage 3 `setcap` | `cap_net_bind_service` on the server binary, so the uid-1000 process binds 80/443 directly, without root or a port-forwarder. |
| Entitle all features | `patches/0001` | Unlocks premium features (licenses, organizations, custom roles) for the self-hosted deployment. |
| Browser-RDP authority | `patches/0002`, `patches/0003`, `overlay/` | Folds the DVLS gateway authority into `coderd`: an RDP launch endpoint + a direct gateway proxy, backed by the dev-kit `jetbroker` core. Pairs with the [`dev-gw`](../dev-gw/) gateway image. |
| Russian UI | `site-patches/` + i18n factory | Optional русификация via the dev-kit `coder-i18n` factory (on by default). |
| Browser-tab titles | `site-patches/0001` | Uses the configured application name in tab titles. |
| README embeds | `site-patches/0002` | Renders `<iframe>` embeds (e.g. interactive guides) in template READMEs. See [README embeds](#readme-embeds). |

## Build architecture

Three stages in [`Dockerfile`](Dockerfile):

1. **Frontend** (`node`, pinned to `$BUILDPLATFORM`) — fetches the pristine
   upstream tag, applies `site-patches/`, optionally runs the i18n factory, then
   builds the React SPA. Frontend patches MUST live here: stage 2 embeds the
   already-built `site/out`, so a stage-2 patch never reaches the bundle.
2. **Server** (`golang`, cross-compiled for `$TARGETARCH`) — fetches the same
   tag, applies the Go `patches/` series, drops in the `overlay/` files and the
   `dev-kit` module dependency, builds the slim agent/CLI binaries into
   `site/out/bin`, then builds the server (`-tags embed`) which `//go:embed`s the
   frontend + agents.
3. **Assemble** — copies `/opt/coder` onto `ghcr.io/coder/coder:${VERSION}` and
   applies `setcap`.

`git apply` fails the build loudly if any patch no longer matches the pinned
`VERSION`, so version drift is caught at build time, not at runtime.

### Patch & overlay layout

```
patches/         Go server patches (stage 2, version-coupled)
  0001-entitle-all-features.patch
  0002-rdp-launch-route.patch
  0003-rdp-gateway-direct-proxy.patch
site-patches/    Frontend patches (stage 1, applied before pnpm build)
  0001-page-title-application-name.patch
  0002-template-readme-embeds.patch
overlay/         New Go files (version-robust, copied not patched)
  coderd/        RDP adapters, gateway config, launch endpoint
  workspaceapps/ RDP gateway direct-proxy helper
```

Overlays are whole new files (no upstream context to drift against); patches are
diffs against upstream lines and are regenerated on a `VERSION` bump.

## Build arguments

| Arg | Default | Purpose |
|-----|---------|---------|
| `VERSION` | `v2.34.1` | Upstream tag fetched, patched, and used as the runtime base. Tracked by Renovate against `ghcr.io/coder/coder`. |
| `I18N` | `ru` | Localization to bake in. Set empty (`--set image-local.args.I18N=`) for the stock English build. |
| `DEV_KIT_VERSION` | `v0.3.0` | [`dev-kit`](https://github.com/astrateam-net/dev-kit) tag for the i18n factory and the `jetbroker` module. |
| `GO_TAGS_COMMON` | `ts_omit_*` | Tailscale feature trims, kept in sync with upstream. |
| `SLIM_OSARCHES` | `linux/darwin/windows :amd64` | Slim agent/CLI targets embedded and served at `/bin/`. |

## README embeds

The template README is rendered by Coder's shared Markdown component, which
drops raw HTML by default — so an `<iframe>` interactive-guide embed in a
template's `README.md` would silently disappear. `site-patches/0002` adds an
opt-in, README-only pipeline (`rehype-raw` → `rehype-sanitize`) that renders
`<iframe>` embeds in template READMEs. Every other Markdown surface keeps the
strict, no-raw-HTML default.

This patch only makes the `<iframe>` render into the page. **Which hosts may
actually load is governed by Coder's `frame-src` CSP**, which defaults to
`'self'` and blocks everything else. There is intentionally no separate
allowlist baked into the image — the CSP is the single source of truth, set at
runtime on the deployment (no rebuild to add a host):

```sh
CODER_ADDITIONAL_CSP_POLICY="frame-src https://guides.astrateam.net"
```

Template authors then paste the embed straight into the template's `README.md`;
nothing in the Terraform → provider → server path inspects or rejects it, and
the browser loads only the CSP-allowed hosts.

## Local development

```sh
./run-local.sh          # builds on demand, runs with built-in PostgreSQL
```

Open the printed URL, create the first admin in the browser, and check the
premium sections (Deployment → Licenses, Organizations, Custom Roles). Data
persists in the `coder-dev-data` volume; remove it to start fresh.

## Testing

`tests.yaml` is a Container Structure Test (structural only — the server needs
PostgreSQL to boot). It verifies the patched binary is present, executable, and
stamped with a real semver version (not a `devel` fallback).

```sh
mise run local-build dev    # build + run structure tests
```
