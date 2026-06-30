# syntax=docker/dockerfile:1

# astrai18n — thin runtime overlay on the upstream tolgee/tolgee image.
#
# No upstream source is rebuilt. A small Byte Buddy agent (built in stage 1) is attached at
# JVM startup via JAVA_TOOL_OPTIONS; it configures the platform's active feature set at runtime.
# The upstream image launches `java ... -cp app:app/lib/* io.tolgee.Application` from /app/cmd.sh,
# which the JVM augments with JAVA_TOOL_OPTIONS automatically — the upstream ENTRYPOINT is kept.

# Global build arg — visible to the FROM line of the final stage.
ARG VERSION

# --- Stage 1: build the self-contained license agent -----------------------
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS agent
WORKDIR /build
COPY agent/ .
RUN mvn -q -B -e -DskipTests package

# --- Stage 2: overlay the agent onto the stock Tolgee image -----------------
# Tag format on Docker Hub is v<semver> (e.g. v3.207.0); VERSION stays pure semver.
FROM docker.io/tolgee/tolgee:v${VERSION}

ARG VERSION
ENV AGENT_PATH=/var/agent

# Tiny agent jar (Byte Buddy NOT bundled) — read-only.
COPY --from=agent --chmod=444 /build/target/astrai18n-agent.jar ${AGENT_PATH}/astrai18n-agent.jar

# Reuse the Byte Buddy the image already ships (Hibernate's, in /app/lib), exposed to the
# agent at premain via the manifest Boot-Class-Path. The [0-9] glob excludes byte-buddy-agent-*.jar.
RUN set -eux; \
    bb="$(ls /app/lib/byte-buddy-[0-9]*.jar | head -n1)"; \
    cp "$bb" ${AGENT_PATH}/byte-buddy.jar; \
    chmod 444 ${AGENT_PATH}/byte-buddy.jar

# JAVA_TOOL_OPTIONS is applied by the JVM on top of any user-supplied JAVA_OPTS, so the
# agent always loads regardless of runtime env overrides.
ENV JAVA_TOOL_OPTIONS="-javaagent:${AGENT_PATH}/astrai18n-agent.jar"

LABEL org.opencontainers.image.title="astrai18n" \
      org.opencontainers.image.description="Self-hosted localization platform for AstraTeam" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"
