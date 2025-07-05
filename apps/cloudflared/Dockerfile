# syntax=docker/dockerfile:1

ARG VERSION
FROM docker.io/cloudflare/cloudflared:${VERSION}

# --- Stage to get busybox for the right arch ---
FROM --platform=$BUILDPLATFORM alpine AS busybox
RUN apk add --no-cache busybox
# Copy the static busybox binary out
RUN cp /bin/busybox /busybox

# --- Final image ---
FROM docker.io/cloudflare/cloudflared:${VERSION}
COPY --from=busybox /busybox /busybox

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /busybox

USER 65532:65532

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]