# syntax=docker/dockerfile:1
# Pangolin EE (postgresql) rebuilt from source with a deterministic exit-node
# subdomain patch.
#
# WHY: stock Pangolin, with `use_subdomain: true`, assigns each exit node a
# RANDOM `adjective-animal` label (server/db/names.ts) that only exists after the
# gerbil registers — so you cannot pre-create its DNS record, which forces the EE
# dynamic authoritative-DNS component. This fork derives the label deterministically
# from the gerbil's own `reachableAt` host, so a static, operator-known name (e.g.
# png01.wg.example.net) is used and you pre-create the DNS A records yourself.
#
# Patches (patches/, applied with `git apply` — the build FAILS LOUDLY on any
# upstream drift from ${VERSION}, so version bumps are caught here, not at runtime):
#   0001  createExitNode (EE): subEndpoint = deterministic label from reachableAt
#         host; upstream random name kept as fallback when reachableAt is absent.
#   0002  copyInConfig: with use_subdomain on, do NOT reset those per-node
#         endpoints back to base_endpoint on every boot (copyInConfig runs each
#         startup — without this the labels are wiped on the first restart).
#
# Build variant matches the upstream `ee-postgresql` image: BUILD=enterprise,
# DATABASE=pg. Runner packaging mirrors upstream's own Dockerfile.

ARG VERSION=1.19.4
ARG NODE_VERSION=24

# ---- fetch pristine upstream source at the tag, apply our patches ----
FROM public.ecr.aws/docker/library/node:${NODE_VERSION}-slim AS source
ARG VERSION
ARG PANGOLIN_REPO=https://github.com/fosrl/pangolin.git
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git init -q . \
    && git remote add origin "${PANGOLIN_REPO}" \
    && git fetch --depth 1 origin "refs/tags/${VERSION}" \
    && git checkout -q FETCH_HEAD
COPY patches/ /patches/
RUN git apply --verbose /patches/*.patch \
    && rm -rf /patches .git

# ---- base toolchain (native deps for the npm build) ----
FROM public.ecr.aws/docker/library/node:${NODE_VERSION}-slim AS base
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
COPY --from=source /app/package*.json ./

# ---- full build (enterprise + postgresql) ----
FROM base AS builder-dev
ARG BUILD=enterprise
ARG DATABASE=pg
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm ci
COPY --from=source /app ./
RUN npm run set:$DATABASE \
    && npm run set:$BUILD \
    && npm run db:generate \
    && npm run build \
    && npm run build:cli \
    && test -f dist/server.mjs

# ---- production dependencies only ----
FROM base AS builder
RUN npm ci --omit=dev

# ---- runner ----
FROM public.ecr.aws/docker/library/node:${NODE_VERSION}-slim AS runner
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder     /app/node_modules ./node_modules
COPY --from=builder     /app/package.json ./package.json
COPY --from=builder-dev /app/.next/standalone ./
COPY --from=builder-dev /app/.next/static ./.next/static
COPY --from=builder-dev /app/dist ./dist
COPY --from=builder-dev /app/server/migrations ./dist/init
COPY --from=builder-dev /app/cli/wrapper.sh /usr/local/bin/pangctl
RUN chmod +x /usr/local/bin/pangctl ./dist/cli.mjs
COPY --from=builder-dev /app/server/db/names.json ./dist/names.json
COPY --from=builder-dev /app/server/db/ios_models.json ./dist/ios_models.json
COPY --from=builder-dev /app/server/db/mac_models.json ./dist/mac_models.json
COPY --from=builder-dev /app/public ./public

# Matches the reference stack's compose healthcheck.
HEALTHCHECK --interval=10s --timeout=10s --retries=15 \
    CMD curl -f http://localhost:3001/api/v1/ || exit 1

CMD ["npm", "run", "start"]
