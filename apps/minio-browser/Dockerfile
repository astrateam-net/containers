# syntax=docker/dockerfile:1
ARG VERSION

FROM node:20 AS build

ARG TARGETARCH

WORKDIR /app

# Clone and checkout specific version
RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser . && \
    git checkout ${VERSION}

# Build web-app
WORKDIR /app/web-app
RUN corepack enable && corepack prepare yarn@4.4.0 --activate && \
    yarn install && yarn build

# Build console
WORKDIR /app
RUN apt-get update && apt-get install -y make curl \
    && GO_VERSION=1.23.0 \
    && if [ "$TARGETARCH" = "amd64" ]; then GOARCH=amd64; else GOARCH=$TARGETARCH; fi \
    && curl -LO https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz \
    && rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-${GOARCH}.tar.gz \
    && export PATH=$PATH:/usr/local/go/bin \
    && /usr/local/go/bin/go version \
    && make console

# Final image
FROM python:alpine

WORKDIR /app

# Create non-root user
RUN addgroup -S appuser && adduser -S appuser -G appuser

# Copy only what we need
COPY --from=build /app/console /app/console
COPY --from=build /app/web-app/build /app/web-app/dist

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 9090

CMD ["./console", "server"]
