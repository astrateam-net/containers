# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## What This Repo Is

A collection of custom Docker images published to `ghcr.io/astrateam-net`. Each app under `/apps/` is independently built and released via GitHub Actions. Renovate automatically updates version pins in `docker-bake.hcl` files.

The repo also contains an embedded Webstudio monorepo at `/webstudio/` — a separate concern with its own toolchain.

---

## Adding a New App

1. Create `apps/<name>/` with `Dockerfile`, `docker-bake.hcl`, and `tests.yaml`.
2. In `docker-bake.hcl`, follow this structure exactly — it's what the CI pipeline parses:

```hcl
target "docker-metadata-action" {}

variable "VERSION" {
  // renovate: datasource=docker depName=<upstream>
  default = "1.2.3"
}

variable "SOURCE" {
  default = "https://github.com/upstream/repo"
}

group "default" { targets = ["image-local"] }

target "image" {
  inherits = ["docker-metadata-action"]
  args = { VERSION = "${VERSION}" }
  labels = { "org.opencontainers.image.source" = "${SOURCE}" }
}

target "image-local" { inherits = ["image"]; output = ["type=docker"] }

target "image-all" {
  inherits = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}
```

3. The `// renovate: datasource=...` comment must be on the line immediately before `default = "..."` for Renovate to pick it up. Common datasources: `datasource=docker`, `datasource=github-releases`, `datasource=github-tags`.
4. If the app version is not upstream-tracked (custom image), omit the Renovate comment and bump `VERSION` manually.
5. Push to `main` — CI triggers on any change under `apps/**`.

---

## Common Commands

Tooling is managed by **mise** (`mise.toml` + tasks in `.mise/tasks/`). Entering the
repo (`mise install`, or `jdx/mise-action` in CI) provisions the toolchain — jq, yq,
goss, container-structure-test — and the `postinstall` hook fetches the matching dgoss
into `.bin/`. No manual tool install step.

```bash
# Provision toolchain + dgoss (usually automatic on `cd` into the repo)
mise install

# Build and test locally (auto-detects goss vs CST)
mise run local-build <app-name>

# Trigger remote build only (no publish)
mise run remote-build <app-name>

# Trigger remote build + publish release
mise run remote-build <app-name> --release

# Generate GitHub labels from apps/
mise run generate-app-labels

# Run mise-task e2e tests
mise run test
```

> **Local build tagging gotcha.** `mise run local-build <app>` runs `docker buildx bake --load`, but the `docker-bake.hcl` targets define **no `tags`**, so each local build is loaded as a **dangling image** (`<none>:<none>`). The recipe runs the structure tests against that fresh image **by digest** — it does **not** create or update any `:local` tag. So a tag like `dev-gw:local` does **not** auto-update and may point at a previous build. To use the image you just built (e.g. in a compose stand), find it with `docker images -a` (newest `<none>` by `CreatedAt`) and tag it yourself: `docker tag <fresh-image-id> dev-gw:local`. Confirm freshness by `Created` time and image content, not by assuming the existing tag is current.

---

## App Structure

```
apps/<name>/
├── Dockerfile        # Multi-stage build; use ARG VERSION for upstream version
├── docker-bake.hcl   # VERSION + SOURCE variables; defines image, image-local, image-all targets
└── tests.yaml        # GOSS (default) or Container Structure Test (requires schemaVersion key)
```

The CI `app-options` action extracts `VERSION`, `SOURCE`, and `platforms` from `docker-bake.hcl` by running `docker buildx bake --list type=variables,format=json`. All three targets (`image`, `image-local`, `image-all`) must be present.

---

## CI Pipeline Summary

| Trigger | Workflow | What happens |
|---------|----------|--------------|
| Push to `main` (apps/** changed) | `release.yaml` | Detect changed apps → build → push with semver + rolling tags → attest → GitHub release (first time only) |
| Pull request | `pull-request.yaml` | Build changed apps only, no push |
| Manual dispatch | `release.yaml` | Build single app, optionally release |
| Daily cron | `vulnerability-scan.yaml` | Grype scan of all `:rolling` images → SARIF upload |

### Versioning

Tags generated per image: `X.Y.Z`, `X.Y`, `X`, `rolling`. Derived from `VERSION` in `docker-bake.hcl` via semver coerce. If `VERSION` is not valid semver, a CalVer date tag is used instead.

### First vs subsequent releases

The `release` job in `app-builder.yaml` only runs when the package does **not yet exist** in GHCR (`app-exists` check). This creates the GitHub Release entry. Subsequent builds skip the release job but still push new image tags.

---

## Testing

- **GOSS**: `tests.yaml` without `schemaVersion` — runtime tests via `dgoss run`
- **CST**: `tests.yaml` with `schemaVersion` — structure tests via `container-structure-test`
- Tests verify ports, HTTP responses, commands, and file system structure.

---

## Code Style

- **PR titles / commits**: Conventional Commits — `feat:`, `fix:`, `build:`, `ci:`, `docs:`
- **Branch naming**: `feature/my-feature-name` or `fix/describe-issue`
- No linting on HCL/YAML beyond schema validation

---

## Webstudio (apps/webstudio + /webstudio/)

Separate monorepo embedded at `/webstudio/`. Stack: React 18, TypeScript 5.8, Remix, PostgreSQL 15, Prisma.

```bash
cd webstudio
pnpm install
pnpm dev          # Start dev server
pnpm checks       # tests + typecheck + lint
pnpm build        # Build all packages
pnpm migrations   # Prisma client + migrations
pnpm storybook:dev  # Storybook on port 6006
```
