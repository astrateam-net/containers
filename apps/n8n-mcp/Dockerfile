# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION
ARG AGENTS_SDK_VERSION=0.3.3
# renovate: datasource=docker depName=node versioning=node
ARG NODE_BUILDER_VERSION=22.22.2-alpine3.22

# Stage 1: rebuild nodes.db with our community node parsed into the catalog.
# Upstream's runtime image ships only a prebuilt nodes.db and strips the n8n
# packages needed to regenerate it, so we rebuild from source at the same tag.
FROM node:${NODE_BUILDER_VERSION} AS db-builder
ARG VERSION
ARG AGENTS_SDK_VERSION
WORKDIR /build
RUN apk add --no-cache git python3 make g++ && \
    git clone --depth 1 --branch v${VERSION} https://github.com/czlonkowski/n8n-mcp.git . && \
    sed -i "/{ name: '@n8n\/n8n-nodes-langchain'/i\    { name: 'n8n-nodes-agents-sdk', path: 'n8n-nodes-agents-sdk' }," src/loaders/node-loader.ts && \
    npm ci && \
    npm install n8n-nodes-agents-sdk@${AGENTS_SDK_VERSION} && \
    npm run build && \
    npm run rebuild

# Stage 2: upstream runtime image, swap in our rebuilt nodes.db.
FROM ghcr.io/czlonkowski/n8n-mcp:${VERSION}
COPY --from=db-builder /build/data/nodes.db /app/data/nodes.db
