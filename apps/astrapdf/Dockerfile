# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Global build args — declared before the first FROM so they are visible to the
# stage base image references below.
ARG VERSION
# SOURCE_REF is the git ref (our fork tag, e.g. astrapdf-2.11.0) carrying the
# AstraPDF patch set on top of upstream VERSION. STIRLING_REPO is our fork.
ARG SOURCE_REF
ARG STIRLING_REPO=https://github.com/mrkhachaturov/Stirling-PDF.git

# --- Stage 1: build the license agent from source ---------------------------
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS agent
WORKDIR /build
COPY agent/ .
RUN mvn -q -B -e -DskipTests package

# --- Stage 2: build the patched proprietary jar from our fork ---------------
# The AstraPDF patch set is currently backend-only (per-user signing certificate
# issuer / step-ca enrolment), living entirely in the proprietary module. We
# compile ONLY that module from the fork at SOURCE_REF and swap its jar into the
# official fat image below — no full Stirling rebuild, the heavy upstream image
# (frontend, OCR, LibreOffice) is reused as-is.
#
# NOTE: this jar-overlay is valid only while the patch stays backend-only and the
# fork is rebased on the SAME upstream tag as VERSION (so the jar filename/version
# matches and the Spring Boot classpath index still resolves it). The moment the
# patch touches the frontend or core/common, replace this stage with a full fat
# build (docker/embedded/Dockerfile.fat) and FROM that instead of the line below.
FROM docker.io/library/gradle:9.3.1-jdk25 AS patch
WORKDIR /src
ARG SOURCE_REF
ARG STIRLING_REPO
ARG STIRLING_REPO_API=https://api.github.com/repos/mrkhachaturov/Stirling-PDF
# Cache-bust for a MOVED tag: SOURCE_REF (e.g. astrapdf-2.11.0) is re-pointed in place as the patch
# iterates on the same upstream base. The git-fetch layer below would otherwise stay cached on its
# unchanged command string and serve stale code. This ADD pulls the ref's current commit metadata,
# whose body changes when the tag moves, invalidating the fetch + build layers. No effect on a
# first/uncached build.
ADD "${STIRLING_REPO_API}/commits/${SOURCE_REF}" /tmp/stirling-ref.json
RUN git init -q . \
    && git remote add origin "${STIRLING_REPO}" \
    && git fetch --depth 1 origin "${SOURCE_REF}" \
    && git checkout -q FETCH_HEAD
RUN DISABLE_ADDITIONAL_FEATURES=false gradle :proprietary:jar \
      -x test -x spotlessApply -x spotlessCheck --no-daemon

# --- Stage 3: overlay onto the official "fat" image -------------------------
# The fat image already bundles OCR (Tesseract + OCRmyPDF), LibreOffice and all
# runtime dependencies. We inject the patched jar + a -javaagent; nothing else is
# rebuilt.
FROM docker.io/stirlingtools/stirling-pdf:${VERSION}-fat

ARG VERSION
USER root

# Swap in the patched proprietary jar. Built on the SAME upstream VERSION, so the
# jar bundled in the image (proprietary-<VERSION>[-plain].jar) keeps its filename
# and the Spring Boot classpath index still resolves it — we only replace its
# bytes. Matched by glob to stay agnostic to Spring Boot's '-plain' classifier;
# the guards fail the build loudly rather than silently no-op'ing.
COPY --from=patch /src/app/proprietary/build/libs/proprietary-${VERSION}*.jar /tmp/proprietary.jar
RUN set -eu; \
    matches="$(find /app -name "proprietary-${VERSION}*.jar")"; \
    count="$(printf '%s\n' "${matches}" | grep -c . || true)"; \
    [ "${count}" = "1" ] || { echo "expected exactly one proprietary jar in /app, found: ${matches:-none}"; exit 1; }; \
    cp /tmp/proprietary.jar "${matches}"; \
    rm /tmp/proprietary.jar

ENV AGENT_PATH=/var/agent
COPY --from=agent /build/target/astrapdf-agent.jar ${AGENT_PATH}/astrapdf-agent.jar
# Reuse the Byte Buddy the fat image already ships (newer than any we'd pin),
# exposed to the agent at premain via its manifest Boot-Class-Path.
RUN cp /app/lib/byte-buddy-*.jar ${AGENT_PATH}/byte-buddy.jar && \
    chmod 444 ${AGENT_PATH}/astrapdf-agent.jar ${AGENT_PATH}/byte-buddy.jar

# The fat image ships only English tessdata; bake in Russian OCR (fast variant,
# matching upstream's eng choice) so OCR ru/en works offline with no startup pull.
RUN curl -fsSL -o /usr/share/tesseract-ocr/5/tessdata/rus.traineddata \
      https://github.com/tesseract-ocr/tessdata_fast/raw/main/rus.traineddata && \
    chmod 444 /usr/share/tesseract-ocr/5/tessdata/rus.traineddata

# JDK_JAVA_OPTIONS is honoured by the java launcher itself, independent of the
# image entrypoint and of JAVA_CUSTOM_OPTS (left free for the operator's heap
# settings in the stack).
ENV JDK_JAVA_OPTIONS="-javaagent:${AGENT_PATH}/astrapdf-agent.jar"

# Generic "secrets via *_FILE" support (Stirling has none upstream), then chain
# into the stock init. Lets any setting come from a Docker/Swarm secret file.
COPY secrets-entrypoint.sh /scripts/secrets-entrypoint.sh
RUN chmod 555 /scripts/secrets-entrypoint.sh
ENTRYPOINT ["tini", "--", "/scripts/secrets-entrypoint.sh"]
