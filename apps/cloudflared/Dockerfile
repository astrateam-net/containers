# syntax=docker/dockerfile:1

ARG VERSION
# FROM docker.io/cloudflare/cloudflared:${VERSION}

# Stage 1: get busybox and prepare entrypoint
FROM alpine AS builder
RUN apk add --no-cache busybox
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /bin/busybox
RUN cp /bin/busybox /busybox

# Stage 2: final image (distroless)
FROM cloudflare/cloudflared:${VERSION}
COPY --from=builder /busybox /busybox
COPY --from=builder /entrypoint.sh /entrypoint.sh

USER 65532:65532

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]