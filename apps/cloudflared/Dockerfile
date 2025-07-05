# syntax=docker/dockerfile:1

ARG VERSION
# FROM docker.io/cloudflare/cloudflared:${VERSION}

# Stage 1: get busybox and prepare entrypoint
FROM alpine AS builder
RUN apk add --no-cache busybox
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /bin/busybox && \
    cp /bin/busybox /busybox && \
    # Check that both files exist and are executable
    [ -x /entrypoint.sh ] && [ -x /busybox ]

# Stage 2: final image (distroless)
FROM docker.io/cloudflare/cloudflared:${VERSION}
COPY --from=builder /busybox /busybox
COPY --from=builder /entrypoint.sh /entrypoint.sh

USER 65532:65532

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]