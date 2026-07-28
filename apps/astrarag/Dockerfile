# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom
ARG VERSION

FROM docker.io/llamaindex/llamacloud-backend:${VERSION} AS upstream

FROM --platform=$BUILDPLATFORM python:3.13-alpine AS patcher
WORKDIR /w
COPY patch.py keys/astrarag_public.pem ./
COPY --from=upstream /app/src/app/license/license_public_key.pub ./app.in
COPY --from=upstream /app/src/usage/license/license_public_key.pub ./usage.in
RUN python patch.py astrarag_public.pem app.in app.out \
 && python patch.py astrarag_public.pem usage.in usage.out

# MCP deps in their own venv: FastMCP needs starlette >=1.0.1, the platform's
# FastAPI pins <1.0.0. Same base image because a venv is not relocatable — its
# pyvenv.cfg points at /usr/bin/python3. --no-config and WORKDIR off /app skip
# upstream's pyproject, which pins resolution to their tailnet package proxy.
FROM docker.io/llamaindex/llamacloud-backend:${VERSION} AS mcpdeps
USER root
WORKDIR /tmp
COPY --from=ghcr.io/astral-sh/uv:0.11.31 /uv /bin/uv
COPY mcp-requirements.txt /tmp/mcp-requirements.txt
RUN ["/bin/uv", "venv", "--no-config", "/opt/mcp/venv", "--python", "/usr/bin/python3"]
RUN ["/bin/uv", "pip", "install", "--no-config", "--python", "/opt/mcp/venv/bin/python", \
     "--requirement", "/tmp/mcp-requirements.txt"]

FROM docker.io/llamaindex/llamacloud-backend:${VERSION}
COPY --from=patcher /w/app.out   /app/src/app/license/license_public_key.pub
COPY --from=patcher /w/usage.out /app/src/usage/license/license_public_key.pub
COPY --from=mcpdeps --chown=65532:65532 /opt/mcp/venv /opt/mcp/venv
