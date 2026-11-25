# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Inbox Zero built from source: upstream docker/Dockerfile.prod at ${VERSION}, with every context COPY
# taken from the `source` stage, which applies patches/ and the AstraTeam brand assets. The 16
# NEXT_PUBLIC_* runtime placeholders are untouched; the flags upstream inlines at build are set below.
# Upstream registers apps/web/app/(marketing) as a submodule without a URL, so the clone skips submodules.
ARG VERSION

FROM alpine/git:2.54.1 AS source
ARG VERSION
WORKDIR /src
RUN git init -q \
 && git remote add origin https://github.com/elie222/inbox-zero.git \
 && git fetch -q --depth 1 origin "${VERSION}" \
 && git checkout -q FETCH_HEAD
COPY patches /patches
COPY brand /brand
RUN git apply --verbose /patches/*.patch \
 && cp /brand/astrateam-logo.svg apps/web/public/brand-logo.svg \
 && cp /brand/icon-512.png apps/web/app/icon.png \
 && cp /brand/icon-512.png apps/web/public/icons/icon-512x512.png \
 && cp /brand/icon-192.png apps/web/public/icons/icon-192x192.png \
 && rm -rf .git


FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS builder

WORKDIR /app

RUN apk add --no-cache openssl
RUN npm install -g pnpm@12.18.0
RUN pnpm config set store-dir /app/.pnpm-store
# Hoisted node_modules so Turbopack resolves packages from the workspace instead
# of following pnpm store symlinks outside package peer dependency boundaries.
# Set as env, not an install flag: pnpm exec verifies deps against the current
# config before running, and a linker mismatch triggers a reinstall into the
# global virtual store that fails with cross-device symlink errors.
ENV pnpm_config_node_linker=hoisted

# Docker build layers are non-interactive; let pnpm handle module purges without a TTY.
ENV CI=true

# Copy lockfiles/workspace manifests for better caching
COPY --from=source /src/package.json /src/pnpm-lock.yaml /src/pnpm-workspace.yaml /src/.npmrc* ./
COPY --from=source /src/patches ./patches
COPY --from=source /src/apps/web/package.json apps/web/package.json
# Lockfile plumbing only; Electron and the unsubscribe worker are not installed.
COPY --from=source /src/apps/desktop/package.json apps/desktop/package.json
COPY --from=source /src/apps/worker/package.json apps/worker/package.json
COPY --from=source /src/apps/unsubscribe-worker/package.json apps/unsubscribe-worker/package.json
COPY --from=source /src/apps/image-proxy/package.json apps/image-proxy/package.json
COPY --from=source /src/apps/image-proxy-aws/package.json apps/image-proxy-aws/package.json
COPY --from=source /src/packages/api/package.json packages/api/package.json
COPY --from=source /src/packages/cli/package.json packages/cli/package.json
COPY --from=source /src/packages/email-editor/package.json packages/email-editor/package.json
COPY --from=source /src/packages/mail-core/package.json packages/mail-core/package.json
COPY --from=source /src/packages/mail-sqlite/package.json packages/mail-sqlite/package.json
COPY --from=source /src/packages/mail-react/package.json packages/mail-react/package.json
COPY --from=source /src/packages/mail-ui/package.json packages/mail-ui/package.json
COPY --from=source /src/packages/image-proxy/package.json packages/image-proxy/package.json
COPY --from=source /src/packages/network/package.json packages/network/package.json
COPY --from=source /src/packages/loops/package.json packages/loops/package.json
COPY --from=source /src/packages/transactional-email/package.json packages/transactional-email/package.json
COPY --from=source /src/packages/scheduling/package.json packages/scheduling/package.json
COPY --from=source /src/packages/tinybird/package.json packages/tinybird/package.json
COPY --from=source /src/packages/tinybird-ai-analytics/package.json packages/tinybird-ai-analytics/package.json
COPY --from=source /src/packages/tsconfig/package.json packages/tsconfig/package.json

# Copy Prisma schema file needed for postinstall script
COPY --from=source /src/apps/web/prisma/schema.prisma apps/web/prisma/schema.prisma
# Copy postinstall script
COPY --from=source /src/clone-marketing.sh clone-marketing.sh
COPY --from=source /src/scripts/pnpm-install-without-desktop.sh scripts/pnpm-install-without-desktop.sh

# Skip @inboxzero/desktop so the image does not download Electron.
RUN chmod +x scripts/pnpm-install-without-desktop.sh \
 && ./scripts/pnpm-install-without-desktop.sh --frozen-lockfile --prefer-offline

 # Copy the full repo
COPY --from=source /src/ .

 # Build app (Next.js standalone)
ENV NODE_ENV=production
# Increase V8 heap for the production build.
ENV NODE_OPTIONS=--max_old_space_size=8192
# Typechecking is covered by the Build Check workflow. Skipping it here
# keeps peak RAM down so Depot workers do not OOM during next build.
ENV SKIP_TYPE_CHECK=true
ARG NEXT_PUBLIC_BASE_URL="http://NEXT_PUBLIC_BASE_URL_PLACEHOLDER"
ENV NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL}
ARG NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS="NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS_PLACEHOLDER"
ENV NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS=${NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS}
ARG NEXT_PUBLIC_EMAIL_SEND_ENABLED="NEXT_PUBLIC_EMAIL_SEND_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_EMAIL_SEND_ENABLED=${NEXT_PUBLIC_EMAIL_SEND_ENABLED}
ARG NEXT_PUBLIC_MAIL_APP_ENABLED="NEXT_PUBLIC_MAIL_APP_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_MAIL_APP_ENABLED=${NEXT_PUBLIC_MAIL_APP_ENABLED}
ARG NEXT_PUBLIC_SELF_HOSTED_LOGIN_FOOTER_TEXT="NEXT_PUBLIC_SELF_HOSTED_LOGIN_FOOTER_TEXT_PLACEHOLDER"
ENV NEXT_PUBLIC_SELF_HOSTED_LOGIN_FOOTER_TEXT=${NEXT_PUBLIC_SELF_HOSTED_LOGIN_FOOTER_TEXT}
ARG NEXT_PUBLIC_CLEANER_ENABLED="NEXT_PUBLIC_CLEANER_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_CLEANER_ENABLED=${NEXT_PUBLIC_CLEANER_ENABLED}
ARG NEXT_PUBLIC_FOLLOW_UP_REMINDERS_ENABLED="NEXT_PUBLIC_FOLLOW_UP_REMINDERS_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_FOLLOW_UP_REMINDERS_ENABLED=${NEXT_PUBLIC_FOLLOW_UP_REMINDERS_ENABLED}
ARG NEXT_PUBLIC_AUTO_DRAFT_DISABLED="NEXT_PUBLIC_AUTO_DRAFT_DISABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_AUTO_DRAFT_DISABLED=${NEXT_PUBLIC_AUTO_DRAFT_DISABLED}
ARG NEXT_PUBLIC_MEETING_BRIEFS_ENABLED="NEXT_PUBLIC_MEETING_BRIEFS_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_MEETING_BRIEFS_ENABLED=${NEXT_PUBLIC_MEETING_BRIEFS_ENABLED}
ARG NEXT_PUBLIC_INTEGRATIONS_ENABLED="NEXT_PUBLIC_INTEGRATIONS_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_INTEGRATIONS_ENABLED=${NEXT_PUBLIC_INTEGRATIONS_ENABLED}
ARG NEXT_PUBLIC_BOOKING_LINKS_ENABLED="NEXT_PUBLIC_BOOKING_LINKS_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_BOOKING_LINKS_ENABLED=${NEXT_PUBLIC_BOOKING_LINKS_ENABLED}
ARG NEXT_PUBLIC_SMART_FILING_ENABLED="NEXT_PUBLIC_SMART_FILING_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_SMART_FILING_ENABLED=${NEXT_PUBLIC_SMART_FILING_ENABLED}
ARG NEXT_PUBLIC_DIGEST_ENABLED="NEXT_PUBLIC_DIGEST_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_DIGEST_ENABLED=${NEXT_PUBLIC_DIGEST_ENABLED}
ARG NEXT_PUBLIC_WEBHOOK_ACTION_ENABLED="NEXT_PUBLIC_WEBHOOK_ACTION_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_WEBHOOK_ACTION_ENABLED=${NEXT_PUBLIC_WEBHOOK_ACTION_ENABLED}
ARG NEXT_PUBLIC_EXTERNAL_API_ENABLED="NEXT_PUBLIC_EXTERNAL_API_ENABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_EXTERNAL_API_ENABLED=${NEXT_PUBLIC_EXTERNAL_API_ENABLED}
ARG NEXT_PUBLIC_AI_MODEL_SETTINGS_DISABLED="NEXT_PUBLIC_AI_MODEL_SETTINGS_DISABLED_PLACEHOLDER"
ENV NEXT_PUBLIC_AI_MODEL_SETTINGS_DISABLED=${NEXT_PUBLIC_AI_MODEL_SETTINGS_DISABLED}

# AstraTeam build-time flags (no runtime placeholder upstream).
ENV NEXT_PUBLIC_INTEGRATION_ACTION_ENABLED=true \
    NEXT_PUBLIC_CONTACTS_ENABLED=true \
    NEXT_PUBLIC_GMAIL_OTHER_CONTACTS_ENABLED=true \
    NEXT_PUBLIC_DELETE_EMAIL_ACTION_ENABLED=true \
    NEXT_PUBLIC_MEETING_RECORDER_ENABLED=true \
    NEXT_PUBLIC_IMAGE_PROXY_USE_APP_ROUTE=true \
    NEXT_PUBLIC_BRAND_NAME=AstraTeam \
    NEXT_PUBLIC_BRAND_LOGO_URL=/brand-logo.svg

# Provide safe dummy envs so Next build can complete at image build time
ENV DATABASE_URL="postgresql://dummy:dummy@dummy:5432/dummy?schema=public"
ENV DIRECT_URL="postgresql://dummy:dummy@dummy:5432/dummy?schema=public"
ENV AUTH_SECRET="dummy_secret_for_build_only_32chars!"
ENV BETTER_AUTH_SECRET="dummy_secret_for_build_only_32chars!"
ENV GOOGLE_CLIENT_ID="dummy_id_for_build_only"
ENV GOOGLE_CLIENT_SECRET="dummy_secret_for_build_only"
ENV EMAIL_ENCRYPT_SECRET="dummy_encrypt_secret_for_build_only"
ENV EMAIL_ENCRYPT_SALT="dummy_encrypt_salt_for_build_only"
ENV GOOGLE_PUBSUB_TOPIC_NAME="dummy_topic_for_build_only"
ENV GOOGLE_PUBSUB_VERIFICATION_TOKEN="dummy_pubsub_token_for_build"
ENV DEFAULT_LLMS="anthropic:claude-sonnet-4-6"
ENV INTERNAL_API_KEY="dummy_apikey_for_build_only"
ENV API_KEY_SALT="dummy_salt_for_build_only"
ENV REDIS_HTTP_URL="http://dummy-redis-for-build:6379"
ENV REDIS_HTTP_TOKEN="dummy_redis_token_for_build"
ENV REDIS_URL="redis://dummy:dummy@dummy:6379"
ENV QSTASH_TOKEN="dummy_qstash_token_for_build"
ENV QSTASH_CURRENT_SIGNING_KEY="dummy_qstash_curr_key_for_build"
ENV QSTASH_NEXT_SIGNING_KEY="dummy_qstash_next_key_for_build"
ENV DOCKER_BUILD="true"

RUN rm -f /app/apps/web/.env && touch /app/apps/web/.env

RUN npx prisma generate --schema=apps/web/prisma/schema.prisma

# Legacy deploy reports the @sqlite.org/sqlite-wasm patch as unused. That patch
# only touches browser worker code, which next build has already bundled.
RUN cd /app/apps/web \
 && pnpm exec lingui extract-template \
 && pnpm exec next build \
 && pnpm exec serwist build serwist.config.mjs \
 && cd /app \
 && export pnpm_config_allow_unused_patches=true \
 && pnpm --filter inbox-zero-ai deploy --legacy --prod /tmp/apps/web \
 && pnpm --filter @inboxzero/worker deploy --legacy --prod /tmp/apps/worker \
 && rm -rf apps/web/.next/cache

RUN rm -f /app/apps/web/.env /app/apps/web/.next/standalone/apps/web/.env

FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS runner

WORKDIR /app

# Install openssl for Prisma
RUN apk add --no-cache openssl

# Copy the standalone server output (contains node_modules subset + server.js)
COPY --from=builder /app/apps/web/.next/standalone ./
# Static assets used by the server
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/prisma ./apps/web/prisma
COPY --from=builder /tmp/apps/web/node_modules ./apps/web/node_modules
COPY --from=builder /tmp/apps/worker ./apps/worker

# Fail the image build if the standalone server is missing traced runtime deps.
RUN test -f apps/web/server.js \
 && node -e "require('node:module').createRequire('/app/apps/web/server.js')('next')"

# Copy runtime scripts
COPY --from=source /src/docker/scripts /app/docker/scripts
RUN chmod +x /app/docker/scripts/*.sh

# Install the Prisma CLI for migrations at the app's version so new schema
# features are understood by `migrate deploy`
COPY --from=source /src/apps/web/package.json /tmp/web-package.json
RUN npm install -g "prisma@$(node -p "require('/tmp/web-package.json').dependencies.prisma")" \
 && rm /tmp/web-package.json
# Set NODE_PATH so prisma/config imports resolve correctly
ENV NODE_PATH=/usr/local/lib/node_modules

EXPOSE 3000

# Default command runs the Next.js server from the standalone bundle
CMD ["/app/docker/scripts/start.sh"]
# Cache bust Fri Nov 21 17:08:13 IST 2025
