# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION
ARG AGENTS_SDK_VERSION=0.5.1
# renovate: datasource=docker depName=node versioning=node
ARG NODE_BUILDER_VERSION=22.23.5-alpine3.24

# Stage 1: patch upstream source, register our community node, rebuild nodes.db + dist.
# Upstream's runtime image ships a prebuilt nodes.db and strips the n8n packages
# needed to regenerate it, so we rebuild from source at the same tag.
FROM node:${NODE_BUILDER_VERSION} AS db-builder
ARG VERSION
ARG AGENTS_SDK_VERSION
WORKDIR /build

# Normalizer: alias `n8n-nodes-agents-sdk.*` <-> `nodes-agents-sdk.*` so DB
# lookups resolve (db parser strips `n8n-` prefix on ingest).
COPY <<'NODE_PATCH' /tmp/patch.js
const fs = require('fs');

const normalizerPath = 'src/utils/node-type-normalizer.ts';
let n = fs.readFileSync(normalizerPath, 'utf8');
if (!n.includes('n8n-nodes-agents-sdk')) {
  const toShortAnchor =
`    if (type.startsWith('n8n-nodes-langchain.')) {
      return type.replace(/^n8n-nodes-langchain\\./, 'nodes-langchain.');
    }`;
  if (!n.includes(toShortAnchor)) throw new Error('normalizer (short form) anchor not found');
  n = n.replace(toShortAnchor, toShortAnchor + `
    if (type.startsWith('n8n-nodes-agents-sdk.')) {
      return type.replace(/^n8n-nodes-agents-sdk\\./, 'nodes-agents-sdk.');
    }`);

  const toFullAnchor =
`    if (type.startsWith('nodes-langchain.')) {
      return type.replace(/^nodes-langchain\\./, '@n8n/n8n-nodes-langchain.');
    }`;
  if (!n.includes(toFullAnchor)) throw new Error('normalizer (full form) anchor not found');
  n = n.replace(toFullAnchor, toFullAnchor + `
    if (type.startsWith('nodes-agents-sdk.')) {
      return type.replace(/^nodes-agents-sdk\\./, 'n8n-nodes-agents-sdk.');
    }`);

  fs.writeFileSync(normalizerPath, n);
}

console.log('patches applied');
NODE_PATCH

RUN apk add --no-cache git python3 make g++ && \
    git clone --depth 1 --branch v${VERSION} https://github.com/czlonkowski/n8n-mcp.git . && \
    sed -i "/{ name: '@n8n\/n8n-nodes-langchain'/i\    { name: 'n8n-nodes-agents-sdk', path: 'n8n-nodes-agents-sdk' }," src/loaders/node-loader.ts && \
    grep -q "name: 'n8n-nodes-agents-sdk'" src/loaders/node-loader.ts && \
    node /tmp/patch.js && \
    npm install --no-audit --no-fund && \
    npm install n8n-nodes-agents-sdk@${AGENTS_SDK_VERSION} && \
    npm run build && \
    npm run rebuild

# Stage 2: upstream runtime, swap in our rebuilt nodes.db + patched dist.
FROM ghcr.io/czlonkowski/n8n-mcp:${VERSION}
COPY --from=db-builder --chown=nodejs:nodejs /build/data/nodes.db /app/data/nodes.db
COPY --from=db-builder --chown=nodejs:nodejs /build/data/nodes.db /app/.db-seed/nodes.db
COPY --from=db-builder --chown=nodejs:nodejs /build/dist /app/dist
