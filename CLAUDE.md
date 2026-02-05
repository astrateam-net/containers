# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository manages Docker container builds for multiple applications. Each app in `/apps/` is independently built and published to `ghcr.io`. The repository also contains an embedded Webstudio monorepo at `/webstudio/`.

## Common Commands

### Container Apps (Main Repository)

```bash
# Initialize tools (downloads goss/dgoss for testing)
task init

# Build and test an app locally
task local-build-<app-name>    # e.g., task local-build-flowise

# Trigger remote build via GitHub Actions
task remote-build-<app-name>

# List all available tasks
task
```

### Webstudio Development

```bash
cd webstudio

# Install dependencies
pnpm install

# Start development server
pnpm dev

# Build all packages
pnpm build

# Run all checks (tests + typecheck + lint)
pnpm checks

# Individual commands
pnpm -r test              # Run tests across all packages
pnpm lint                 # ESLint with zero warnings tolerance
pnpm format               # Format with Prettier

# Database
pnpm migrations           # Generate Prisma client + run migrations

# Storybook
pnpm storybook:dev        # Start on port 6006
```

## Architecture

### Container Apps Structure

Each app in `/apps/<name>/` contains:
- `Dockerfile` - Multi-stage build
- `docker-bake.hcl` - Build configuration with VERSION variable (Renovate auto-updates this)
- `tests.yaml` - Container tests (GOSS format for runtime tests, CST format for structure tests)

The Taskfile auto-detects the test tool based on `tests.yaml` format:
- Has `schemaVersion` → Container Structure Test (CST)
- No `schemaVersion` → GOSS

### Webstudio Architecture

A monorepo with 30+ packages at `/webstudio/packages/`:
- `builder` - Main application (Remix)
- `design-system` - UI component library
- `react-sdk` - React SDK for projects
- `prisma-client` - Database client
- `sdk-components-*` - Component libraries (react, radix, remix, router, animation)

Stack: React 18 (canary), TypeScript 5.8, Remix, PostgreSQL 15, Prisma, PostgREST

## Code Style

- **PR titles**: Follow Conventional Commits (`feat:`, `fix:`, `docs:`, `build:`, `ci:`, etc.)
- **Branch naming**: `feature/my-feature-name`
- **Webstudio**: ESLint with strict rules, Prettier with `babel-ts` parser for TypeScript
- **Pre-commit hooks**: Prettier runs automatically on staged files

## Testing

Container tests verify:
- Port availability and HTTP responses
- Command execution and exit status
- File system structure

All containers are built for both `linux/amd64` and `linux/arm64` platforms.
