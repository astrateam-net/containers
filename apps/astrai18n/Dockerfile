# syntax=docker/dockerfile:1


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


RUN set -eux; \
    java -cp "${AGENT_PATH}/astrai18n-agent.jar:/app:/app/lib/*" \
      net.astrateam.astrai18n.VerifyAnchors

# JAVA_TOOL_OPTIONS is applied by the JVM on top of any user-supplied JAVA_OPTS, so the
# agent always loads regardless of runtime env overrides.
ENV JAVA_TOOL_OPTIONS="-javaagent:${AGENT_PATH}/astrai18n-agent.jar"

# Wrap the stock entrypoint to resolve <VAR>_FILE secrets (Docker/Swarm secrets in
# /run/secrets) into the environment before launch; the wrapper ends with
# `exec /app/cmd.sh`, so the upstream Java launch — and JAVA_TOOL_OPTIONS above — is
# preserved verbatim. The upstream image has no native file-secret support.
COPY --chmod=555 file-secrets.sh /app/astrai18n-file-secrets.sh
COPY --chmod=555 entrypoint.sh /app/astrai18n-entrypoint.sh
ENTRYPOINT ["/app/astrai18n-entrypoint.sh"]

LABEL org.opencontainers.image.title="astrai18n" \
      org.opencontainers.image.description="Self-hosted localization platform for AstraTeam" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"
