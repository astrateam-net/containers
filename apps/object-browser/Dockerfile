# syntax=docker/dockerfile:1

ARG VERSION
FROM node:18-bullseye AS builder

WORKDIR /app

RUN git clone https://github.com/OpenMaxIO/openmaxio-object-browser . && \
    git checkout ${VERSION}

WORKDIR /app/web-app
RUN yarn install && \
    yarn build

WORKDIR /app
RUN make console

FROM node:18-bullseye-slim

WORKDIR /app

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser

COPY --from=builder /app/console /app/console
COPY --from=builder /app/web-app/dist /app/web-app/dist

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 8080

CMD ["./console", "server"]
