# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/library/node:20-bookworm AS builder

# Redeclare ARG in this stage so it's available in RUN commands
ARG VERSION

# Install pnpm and git
RUN corepack enable && corepack prepare pnpm@9.14.4 --activate && \
    apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone webstudio repository using version tag
# VERSION should match GitHub release tag (e.g., "0.235.0" or "v0.235.0")
# Using manual git clone to skip submodules (ADD tries to clone submodules and fails on private SSH repo)
# The code handles missing private-src gracefully with fallbacks
# Try with 'v' prefix first, fallback to without prefix
RUN set -e; \
    if git clone --depth 1 --single-branch --branch v${VERSION} https://github.com/webstudio-is/webstudio.git . 2>/dev/null; then \
        echo "Cloned with v${VERSION} tag"; \
    elif git clone --depth 1 --single-branch --branch ${VERSION} https://github.com/webstudio-is/webstudio.git .; then \
        echo "Cloned with ${VERSION} tag"; \
    else \
        echo "ERROR: Failed to clone tag v${VERSION} or ${VERSION}"; \
        exit 1; \
    fi && \
    rm -rf .git

# Install dependencies
RUN pnpm install --frozen-lockfile

# Generate Prisma client (required before build)
# This must be done before building since prisma-client package imports from __generated__
# Set binary target for Debian Linux (glibc)
ENV PRISMA_BINARY_TARGET='["native","debian-openssl-3.0.x"]'
RUN pnpm --filter=@webstudio-is/prisma-client generate

# Build all packages and apps
RUN pnpm build

# Final stage
FROM docker.io/library/node:20-bookworm

# Install Docker-in-Docker using the official devcontainer script
# This script handles all Docker installation and creates docker-init.sh
# Copy the script from the webstudio repo (it's already there)
COPY --from=builder /app/.devcontainer/library-scripts/docker-in-docker-debian.sh /tmp/library-scripts/docker-in-docker-debian.sh

# Run the docker-in-docker installation script
# This will install Docker and create /usr/local/share/docker-init.sh
ENV DOCKER_BUILDKIT=1
RUN chmod +x /tmp/library-scripts/docker-in-docker-debian.sh && \
    /bin/bash /tmp/library-scripts/docker-in-docker-debian.sh

# Note: docker-init.sh is created by the script above
# IMPORTANT: The container must be run with --privileged flag for Docker-in-Docker to work
# Example: docker run --privileged your-image
# This is required because Supabase CLI and other tools need Docker to execute containers

# Install pnpm
RUN corepack enable && corepack prepare pnpm@9.14.4 --activate

WORKDIR /app

# Copy workspace structure (package files and built artifacts)
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/patches ./patches
COPY --from=builder /app/apps ./apps
COPY --from=builder /app/packages ./packages

# Install production dependencies only
# This will set up workspace links correctly
RUN pnpm install --frozen-lockfile --prod

# Install runtime tools globally for migrations
# Prisma CLI: needed for generating Prisma client and running migrations
# tsx: needed for running TypeScript migration scripts
# Use npm instead of pnpm for global installs (pnpm requires setup for global bin directory)
RUN npm install -g prisma@5.12.1 tsx@^4.19.2

# Set Prisma binary target for Debian Linux (needed for runtime Prisma client generation)
ENV PRISMA_BINARY_TARGET='["native","debian-openssl-3.0.x"]'

# Copy entrypoint script for migrations and app startup
# Note: docker-init.sh is already created by docker-in-docker-debian.sh script above
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables
# DATABASE_URL: PostgreSQL connection string (required)
# POSTGREST_URL: PostgREST API URL (default: http://localhost:3000)
# POSTGREST_API_KEY: PostgREST API key (optional)
# RUN_MIGRATIONS: Set to "true" to run migrations on startup (optional)
ENV NODE_ENV=production \
    PORT=3000 \
    POSTGREST_URL=http://localhost:3000 \
    RUN_MIGRATIONS=false

EXPOSE 3000

# Use entrypoint script to optionally run migrations before starting
# Run start command from workspace root using filter to target builder app
ENTRYPOINT ["/entrypoint.sh"]
CMD ["pnpm", "--filter", "@webstudio-is/builder", "start"]

