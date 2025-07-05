# syntax=docker/dockerfile:1

ARG VERSION=2025.7.0
ARG TARGETPLATFORM

FROM --platform=$TARGETPLATFORM alpine AS builder
RUN apk add --no-cache busybox
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /bin/busybox && cp /bin/busybox /busybox

# Test stage: check that /entrypoint.sh and /busybox are present and executable, and /busybox works
FROM builder AS test
RUN [ -x /entrypoint.sh ] && [ -x /busybox ] && /busybox echo ok && /busybox uname -m

FROM cloudflare/cloudflared:${VERSION}
COPY --from=builder /busybox /busybox
COPY --from=builder /entrypoint.sh /entrypoint.sh

USER 65532:65532
ENTRYPOINT ["/entrypoint.sh"]
CMD ["tunnel", "--no-autoupdate"]
