ARG VERSION

FROM alpine:3.21

ARG VERSION

RUN apk add --no-cache \
    curl \
    jq \
    git \
    openssh-client

RUN curl -fsSL https://get.opentofu.org/install-opentofu.sh | sh -s -- \
    --install-method standalone \
    --opentofu-version ${VERSION}

RUN tofu version

ENTRYPOINT ["/bin/sh"]
