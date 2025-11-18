# syntax=docker/dockerfile:1

ARG VERSION
ARG GIT_REF=master
FROM docker.io/library/node:22-alpine AS builder

WORKDIR /app

# Clone penpot-mcp repository using Docker ADD (supports branches/commits)
ADD https://github.com/penpot/penpot-mcp.git#${GIT_REF} .

# Install root dependencies
RUN npm ci

# Install dependencies for all components
RUN npm run install:all

# Build all components
RUN npm run build:all

# Build plugin for production (not watch mode)
WORKDIR /app/penpot-plugin
RUN npm run build

# Final stage
FROM docker.io/library/node:22-alpine

WORKDIR /app

# Install production dependencies only
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/common/package*.json ./common/
COPY --from=builder /app/mcp-server/package*.json ./mcp-server/
COPY --from=builder /app/penpot-plugin/package*.json ./penpot-plugin/

RUN npm ci --omit=dev && \
    npm --prefix common ci --omit=dev && \
    npm --prefix mcp-server ci --omit=dev && \
    npm --prefix penpot-plugin ci --omit=dev

# Copy built artifacts
COPY --from=builder /app/common/dist ./common/dist
COPY --from=builder /app/mcp-server/dist ./mcp-server/dist
COPY --from=builder /app/mcp-server/data ./mcp-server/data
COPY --from=builder /app/penpot-plugin/dist ./penpot-plugin/dist
COPY --from=builder /app/penpot-plugin/public ./penpot-plugin/public
COPY --from=builder /app/penpot-plugin/index.html ./penpot-plugin/
COPY --from=builder /app/penpot-plugin/vite.config.ts ./penpot-plugin/

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Install vite globally for preview server
RUN npm install -g vite@^7.0.5

# Environment variables for configuration
# MCP_PORT: Port for MCP server (default: 4401)
# PLUGIN_PORT: Port for plugin server (default: 4400)
ENV MCP_PORT=4401 \
    PLUGIN_PORT=4400

EXPOSE 4400 4401

ENTRYPOINT ["/entrypoint.sh"]

