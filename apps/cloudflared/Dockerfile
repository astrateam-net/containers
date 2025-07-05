# syntax=docker/dockerfile:1

ARG VERSION=2025.7.0
ARG TARGETPLATFORM

FROM --platform=$TARGETPLATFORM alpine AS builder
RUN apk add --no-cache busybox
RUN mkdir -p /opt/bin
COPY entrypoint.sh /opt/bin/entrypoint.sh
RUN chmod +x /opt/bin/entrypoint.sh /bin/busybox && cp /bin/busybox /opt/bin/busybox

FROM cloudflare/cloudflared:${VERSION}
USER root
COPY --from=builder /opt/bin /opt/bin
USER 65532:65532
ENTRYPOINT ["/opt/bin/busybox", "sh", "/opt/bin/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]
