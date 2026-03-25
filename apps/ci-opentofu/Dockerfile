ARG VERSION

FROM ghcr.io/opentofu/opentofu:${VERSION}-minimal AS tofu

FROM alpine:3.21

COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu

RUN apk add --no-cache \
    curl \
    jq \
    git \
    openssh-client

RUN tofu version

ENTRYPOINT ["/bin/sh"]
