# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION
ARG AGENTS_SDK_VERSION=0.3.3
# renovate: datasource=docker depName=node versioning=node
ARG NODE_BUILDER_VERSION=22.22.2-alpine3.22

# Stage 1: patch upstream source, register our community node, rebuild nodes.db + dist.
# Upstream's runtime image ships a prebuilt nodes.db and strips the n8n packages
# needed to regenerate it, so we rebuild from source at the same tag.
FROM node:${NODE_BUILDER_VERSION} AS db-builder
ARG VERSION
ARG AGENTS_SDK_VERSION
WORKDIR /build

# Surgical whitelist patches for n8n-nodes-agents-sdk — zero behavior change for
# n8n-nodes-base, @n8n/n8n-nodes-langchain, or any other community package:
#   1. Normalizer: alias `n8n-nodes-agents-sdk.*` <-> `nodes-agents-sdk.*` so
#      DB lookups resolve (db parser strips `n8n-` prefix on ingest).
#   2. Workflow validator: exclude our package from the "AI Agent has no tools
#      connected" heuristic, which fires on any type containing "agent".
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

const validatorPath = 'src/services/workflow-validator.ts';
let v = fs.readFileSync(validatorPath, 'utf8');
if (!v.includes("!n.type.includes('nodes-agents-sdk.')")) {
  const before =
`    const aiAgentNodes = workflow.nodes.filter(n =>
      n.type.toLowerCase().includes('agent') ||
      n.type.includes('langchain.agent')
    );`;
  const after =
`    const aiAgentNodes = workflow.nodes.filter(n =>
      !n.type.includes('nodes-agents-sdk.') && (
        n.type.toLowerCase().includes('agent') ||
        n.type.includes('langchain.agent')
      )
    );`;
  if (!v.includes(before)) throw new Error('validator anchor not found');
  v = v.replace(before, after);
  fs.writeFileSync(validatorPath, v);
}

console.log('patches applied');
NODE_PATCH

RUN apk add --no-cache git python3 make g++ && \
    git clone --depth 1 --branch v${VERSION} https://github.com/czlonkowski/n8n-mcp.git . && \
    sed -i "/{ name: '@n8n\/n8n-nodes-langchain'/i\    { name: 'n8n-nodes-agents-sdk', path: 'n8n-nodes-agents-sdk' }," src/loaders/node-loader.ts && \
    node /tmp/patch.js && \
    npm ci && \
    npm install n8n-nodes-agents-sdk@${AGENTS_SDK_VERSION} && \
    npm run build && \
    npm run rebuild

# Stage 2: upstream runtime, swap in our rebuilt nodes.db + patched dist.
FROM ghcr.io/czlonkowski/n8n-mcp:${VERSION}
COPY --from=db-builder /build/data/nodes.db /app/data/nodes.db
COPY --from=db-builder /build/dist /app/dist
