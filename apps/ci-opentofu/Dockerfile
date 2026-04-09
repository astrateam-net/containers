# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

ARG VERSION

FROM ghcr.io/opentofu/opentofu:${VERSION}-minimal AS tofu

FROM alpine:3.21

ARG PROXMOX_PROVIDER_VERSION

COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu

RUN apk add --no-cache \
    curl \
    jq \
    git \
    openssh-client

# Pre-download bpg/proxmox provider into a filesystem mirror
RUN mkdir -p /tmp/mirror-src && \
    printf 'terraform {\n  required_providers {\n    proxmox = {\n      source  = "bpg/proxmox"\n      version = "%s"\n    }\n  }\n}\n' "${PROXMOX_PROVIDER_VERSION}" > /tmp/mirror-src/providers.tf && \
    tofu -chdir=/tmp/mirror-src providers mirror -platform=linux_amd64 -platform=linux_arm64 /usr/share/terraform/providers && \
    rm -rf /tmp/mirror-src

# Configure tofu to use the filesystem mirror first, then fall back to registry
RUN printf 'provider_installation {\n  filesystem_mirror {\n    path = "/usr/share/terraform/providers"\n  }\n  direct {}\n}\n' > /etc/tofurc

ENV TF_CLI_CONFIG_FILE=/etc/tofurc

RUN tofu version
