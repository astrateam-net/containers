# syntax=docker/dockerfile:1

ARG VERSION
FROM node:18-bullseye AS builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Go
RUN wget https://go.dev/dl/go1.22.1.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.22.1.linux-amd64.tar.gz && \
    rm go1.22.1.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser . && \
    git checkout ${VERSION}

WORKDIR /app/web-app
RUN corepack enable && \
    corepack prepare yarn@4.4.0 --activate && \
    yarn install && \
    npx update-browserslist-db@latest && \
    yarn build && \
    ls -la build/

WORKDIR /app
RUN make console

FROM node:18-bullseye-slim

WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

COPY --from=builder /app/console /app/console
COPY --from=builder /app/web-app/build /app/web-app/dist

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

CMD ["./console", "server"]
