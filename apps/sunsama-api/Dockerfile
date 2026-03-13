# syntax=docker/dockerfile:1

ARG VERSION
ARG GIT_REF=main
FROM docker.io/library/node:24-alpine AS builder

# Redeclare ARG after FROM to make it available in this stage
ARG GIT_REF

WORKDIR /app

# Enable corepack for pnpm
RUN corepack enable

# Clone sunsama-http-api-server repository
# Using git clone since the repo has no tags, we clone from the main branch
RUN apk add --no-cache git && \
    git clone --depth 1 --single-branch --branch "${GIT_REF:-main}" \
        https://github.com/mrkhachaturov/sunsama-http-api-server.git . && \
    rm -rf .git

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build TypeScript (creates dist/esm, dist/cjs, dist/types)
RUN pnpm build

# Production stage
FROM docker.io/library/node:24-alpine

WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S sunsama -u 1001

# Copy built files and production dependencies
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

# Set ownership
RUN chown -R sunsama:nodejs /app

# Switch to non-root user
USER sunsama

# Environment variables
# PORT: Server port (default: 3000)
# HOST: Bind address (default: 0.0.0.0)
# API_KEY_<key>: Direct credentials format: email:password
# API_KEY_<key>_FILE: Path to file containing email:password (for Docker secrets)
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:${PORT:-3000}/health || exit 1

# Start the server
CMD ["node", "dist/esm/server/index.js"]

