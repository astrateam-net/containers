# syntax=docker/dockerfile:1

ARG VERSION
FROM ghcr.io/n8n-io/n8n:${VERSION}
ARG NODE_VERSION=24
ARG BASE_URL=/

# Build stage for n8n-editor-ui
FROM --platform=linux/amd64 n8nio/base:${NODE_VERSION} AS builder

WORKDIR /src
RUN git clone https://github.com/n8n-io/n8n.git /src

# Set environment variables for the build
ENV VUE_APP_URL_BASE_API=${BASE_URL}
ENV DOCKER_BUILD=true

RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store --mount=type=cache,id=pnpm-metadata,target=/root/.cache/pnpm/metadata pnpm install --frozen-lockfile

# Build only the editor-ui package
RUN cd packages/frontend/editor-ui && pnpm build

# Final stage
FROM ghcr.io/n8n-io/n8n:${VERSION}

# Copy the built UI from the builder stage
COPY --from=builder /src/packages/frontend/editor-ui/dist /usr/local/lib/node_modules/n8n/packages/frontend/editor-ui/dist

