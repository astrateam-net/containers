# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Global build arg — declared before the first FROM so it is visible to the
# stage 2 base image reference below.
ARG VERSION

# --- Stage 1: build the license agent from source ---------------------------
FROM docker.io/library/maven:3.9-eclipse-temurin-21 AS agent
WORKDIR /build
COPY agent/ .
RUN mvn -q -B -e -DskipTests package

# --- Stage 2: overlay the agent onto the official "fat" image ---------------
# The fat image already bundles OCR (Tesseract + OCRmyPDF), LibreOffice and all
# runtime dependencies. We only inject a -javaagent; nothing is rebuilt.
FROM docker.io/stirlingtools/stirling-pdf:${VERSION}-fat

USER root

ENV AGENT_PATH=/var/agent
COPY --from=agent /build/target/astrapdf-agent.jar ${AGENT_PATH}/astrapdf-agent.jar
# Reuse the Byte Buddy the fat image already ships (newer than any we'd pin),
# exposed to the agent at premain via its manifest Boot-Class-Path.
RUN cp /app/lib/byte-buddy-*.jar ${AGENT_PATH}/byte-buddy.jar && \
    chmod 444 ${AGENT_PATH}/astrapdf-agent.jar ${AGENT_PATH}/byte-buddy.jar

# JDK_JAVA_OPTIONS is honoured by the java launcher itself, independent of the
# image entrypoint and of JAVA_CUSTOM_OPTS (left free for the operator's heap
# settings in the stack).
ENV JDK_JAVA_OPTIONS="-javaagent:${AGENT_PATH}/astrapdf-agent.jar"
