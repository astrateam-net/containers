# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# AstraPDF — full "fat" build from our Stirling-PDF fork (frontend + backend), assembled onto the
# upstream pre-built base image.
#
# Replaces the previous proprietary-jar overlay. The AstraPDF patch set now spans core/common AND
# the frontend (per-user "Personal" certificate in the standalone Certificate Sign tool, RFC 3161
# signature timestamping, plus the Shared Signing UI which the official fat image's frontend bundle
# omits) — only a full app rebuild ships them. The heavy base (LibreOffice, Tesseract, Calibre) is
# NOT rebuilt: we reuse stirlingtools/stirling-pdf-base, so this stays a fast app-only rebuild.

# Global build args — visible to the stage FROM lines below.
ARG VERSION
ARG BASE_VERSION=1.0.2
ARG BASE_IMAGE=docker.io/stirlingtools/stirling-pdf-base:${BASE_VERSION}
# SOURCE_REF is the git ref on our fork (e.g. tag astrapdf-2.11.0) carrying the patch set on top of
# upstream VERSION. STIRLING_REPO is our fork.
ARG SOURCE_REF
ARG STIRLING_REPO=https://github.com/mrkhachaturov/Stirling-PDF.git

# --- Stage 1: build the license agent from source ---------------------------
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS agent
WORKDIR /build
COPY agent/ .
RUN mvn -q -B -e -DskipTests package

# --- Stage 2: build the patched app (frontend + backend) from our fork -------
# Mirrors the fork's docker/embedded/Dockerfile.fat app-build stage, but pulls the source by git ref
# instead of a build-context COPY. Installs Node + Task because -PbuildWithFrontend=true compiles the
# React frontend and embeds it into the Spring Boot jar.
# Keep this Gradle version matched to the fork's wrapper: `gradle` is invoked directly below, so the
# image's Gradle wins over gradle/wrapper/gradle-wrapper.properties. Upstream 2.14.2 builds on 9.6.0.
FROM docker.io/library/gradle:9.6.0-jdk25 AS app-build
ARG TASK_VERSION=3.49.1
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates git \
    && update-ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_${TASK_VERSION}_linux_${ARCH}.deb" -o /tmp/task.deb \
    && dpkg -i /tmp/task.deb \
    && rm /tmp/task.deb \
    && rm -rf /var/lib/apt/lists/*

# JDK 25+: --add-exports is no longer accepted via JAVA_TOOL_OPTIONS; use JDK_JAVA_OPTIONS instead.
ENV JDK_JAVA_OPTIONS="--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED \
  --add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED \
  --add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED \
  --add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED \
  --add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED"

WORKDIR /app
ARG SOURCE_REF
ARG STIRLING_REPO
ARG STIRLING_REPO_API=https://api.github.com/repos/mrkhachaturov/Stirling-PDF
# Cache-bust for a MOVED tag: SOURCE_REF (e.g. astrapdf-2.11.0) is re-pointed in place as the patch
# iterates on the same upstream base. This ADD pulls the ref's current commit metadata, whose body
# changes when the tag moves, invalidating the fetch + build layers. No effect on a first build.
ADD "${STIRLING_REPO_API}/commits/${SOURCE_REF}" /tmp/stirling-ref.json
RUN git init -q . \
    && git remote add origin "${STIRLING_REPO}" \
    && git fetch --depth 1 origin "${SOURCE_REF}" \
    && git checkout -q FETCH_HEAD

RUN DISABLE_ADDITIONAL_FEATURES=false \
    gradle clean build \
      -PbuildWithFrontend=true \
      -x spotlessApply -x spotlessCheck -x test -x sonarqube \
      --no-daemon

# --- Stage 3: extract Spring Boot layers ------------------------------------
FROM docker.io/library/eclipse-temurin:25-jre-noble AS jar-extract
WORKDIR /tmp
COPY --from=app-build /app/app/core/build/libs/*.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination /layers

# --- Stage 4: final runtime image on the upstream pre-built base ------------
FROM ${BASE_IMAGE}

ARG VERSION
USER root
WORKDIR /app

# Application layers (from the rebuilt fork jar — carries our backend + the embedded frontend)
COPY --link --from=jar-extract --chown=1000:1000 /layers/dependencies/           /app/
COPY --link --from=jar-extract --chown=1000:1000 /layers/spring-boot-loader/     /app/
COPY --link --from=jar-extract --chown=1000:1000 /layers/snapshot-dependencies/  /app/
COPY --link --from=jar-extract --chown=1000:1000 /layers/application/            /app/

COPY --link --from=app-build --chown=1000:1000 /app/build/libs/restart-helper.jar /restart-helper.jar
COPY --link --from=app-build --chown=1000:1000 /app/scripts/ /scripts/

# Fonts go to the system dir (world-readable, root-owned)
COPY --from=app-build /app/app/core/src/main/resources/static/fonts/*.ttf /usr/share/fonts/truetype/

# Permissions and configuration (mirrors the upstream fat final stage)
RUN set -eux; \
    chmod +x /scripts/*; \
    ln -s /logs /app/logs; \
    ln -s /configs /app/configs; \
    ln -s /customFiles /app/customFiles; \
    ln -s /pipeline /app/pipeline; \
    chown -h stirlingpdfuser:stirlingpdfgroup /app/logs /app/configs /app/customFiles /app/pipeline; \
    chown stirlingpdfuser:stirlingpdfgroup /app; \
    chmod 750 /tmp/stirling-pdf; \
    chmod 750 /tmp/stirling-pdf/heap_dumps; \
    fc-cache -f

RUN echo "${VERSION:-dev}" > /etc/stirling_version

# --- AstraPDF overlay: license agent, Russian OCR, secrets-via-FILE ---------
ENV AGENT_PATH=/var/agent
COPY --from=agent /build/target/astrapdf-agent.jar ${AGENT_PATH}/astrapdf-agent.jar
# Reuse the Byte Buddy the runtime already ships, exposed to the agent at premain.
RUN cp /app/lib/byte-buddy-*.jar ${AGENT_PATH}/byte-buddy.jar 2>/dev/null \
      || cp "$(find /app -name 'byte-buddy-*.jar' | head -n1)" ${AGENT_PATH}/byte-buddy.jar; \
    chmod 444 ${AGENT_PATH}/astrapdf-agent.jar ${AGENT_PATH}/byte-buddy.jar

# The base ships only English tessdata; bake in Russian OCR (fast variant) so OCR ru/en works
# offline with no startup pull.
RUN curl -fsSL -o /usr/share/tesseract-ocr/5/tessdata/rus.traineddata \
      https://github.com/tesseract-ocr/tessdata_fast/raw/main/rus.traineddata && \
    chmod 444 /usr/share/tesseract-ocr/5/tessdata/rus.traineddata

# Environment (mirrors the upstream fat final stage; JDK_JAVA_OPTIONS additionally loads our agent)
ENV VERSION_TAG=$VERSION \
    STIRLING_AOT_ENABLE="false" \
    STIRLING_JVM_PROFILE="balanced" \
    _JVM_OPTS_BALANCED="-XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/configs/heap_dumps -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:G1HeapRegionSize=4m -XX:G1PeriodicGCInterval=60000 -XX:+UseStringDeduplication -XX:+UseCompactObjectHeaders -XX:+ExplicitGCInvokesConcurrent -Dspring.threads.virtual.enabled=true -Djava.awt.headless=true" \
    _JVM_OPTS_PERFORMANCE="-XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/configs/heap_dumps -XX:+UseShenandoahGC -XX:ShenandoahGCMode=generational -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication -XX:+AlwaysPreTouch -XX:+ExplicitGCInvokesConcurrent -Dspring.threads.virtual.enabled=true -Djava.awt.headless=true" \
    JAVA_CUSTOM_OPTS="" \
    JDK_JAVA_OPTIONS="-javaagent:${AGENT_PATH}/astrapdf-agent.jar" \
    HOME=/home/stirlingpdfuser \
    PUID=1000 \
    PGID=1000 \
    UMASK=022 \
    FAT_DOCKER=true \
    INSTALL_BOOK_AND_ADVANCED_HTML_OPS=false \
    STIRLING_TEMPFILES_DIRECTORY=/tmp/stirling-pdf \
    TMPDIR=/tmp/stirling-pdf \
    TEMP=/tmp/stirling-pdf \
    TMP=/tmp/stirling-pdf \
    DBUS_SESSION_BUS_ADDRESS=/dev/null \
    SAL_TMP=/tmp/stirling-pdf/libre

LABEL org.opencontainers.image.title="AstraPDF" \
      org.opencontainers.image.description="AstraTeam Stirling-PDF fat build: per-user step-ca signing, signature timestamping, Shared Signing UI, OCR ru/en, Enterprise features" \
      org.opencontainers.image.vendor="astrateam-net" \
      org.opencontainers.image.version="${VERSION}"

EXPOSE 8080/tcp
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=15s --start-period=180s --retries=5 \
  CMD curl -fs --max-time 10 http://localhost:8080${SYSTEM_ROOTURIPATH:-''}/api/v1/info/status || exit 1

# Generic "secrets via *_FILE" support + Root CA import for in-app signature validation, then chain
# into the stock init. Runs as root before init.sh drops privileges.
COPY secrets-entrypoint.sh /scripts/secrets-entrypoint.sh
RUN chmod 555 /scripts/secrets-entrypoint.sh
ENTRYPOINT ["tini", "--", "/scripts/secrets-entrypoint.sh"]
CMD []
