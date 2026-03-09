# syntax=docker/dockerfile:1

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

LABEL maintainer="homelab-am"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PIP_ROOT_USER_ACTION=ignore \
    AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache \
    PATH=/opt/ansible-venv/bin:/actions-runner:${PATH} \
    RUN_AS_ROOT=false

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GH_RUNNER_VERSION=2.332.0
ARG TARGETPLATFORM

RUN \
    apt-get -qq update \
    && \
    apt-get -qq install -y --no-install-recommends --no-install-suggests \
        ca-certificates \
        curl \
        dumb-init \
        git \
        gosu \
        jq \
        locales \
        openssh-client \
        openssl \
        python3 \
        python3-pip \
        python3-venv \
        rsync \
        sudo \
        tar \
        unzip \
        zip \
    && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && \
    locale-gen \
    && \
    groupadd -g 121 runner \
    && \
    useradd -mr -d /home/runner -u 1001 -g 121 runner \
    && \
    usermod -aG sudo runner \
    && \
    mkdir -p /actions-runner /_work /opt/hostedtoolcache /usr/share/ansible/collections \
    && \
    chown -R runner:runner /actions-runner /_work /opt/hostedtoolcache \
    && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /actions-runner

COPY install_actions.sh /actions-runner/install_actions.sh
RUN \
    chmod +x /actions-runner/install_actions.sh \
    && \
    /actions-runner/install_actions.sh "${GH_RUNNER_VERSION}" "${TARGETPLATFORM}" \
    && \
    rm -f /actions-runner/install_actions.sh

COPY requirements.txt /tmp/requirements.txt
COPY ansible-requirements.yml /tmp/ansible-requirements.yml
RUN \
    python3 -m venv /opt/ansible-venv \
    && \
    /opt/ansible-venv/bin/pip install --upgrade pip \
    && \
    /opt/ansible-venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && \
    for collection in community.library_inventory_filtering_v1:1.1.5 community.docker:4.8.2; do \
        for attempt in 1 2 3 4 5 6 7 8; do \
            /opt/ansible-venv/bin/ansible-galaxy collection install --timeout 180 "${collection}" -p /usr/share/ansible/collections && break; \
            if [ "$attempt" -eq 8 ]; then \
                echo "ansible-galaxy collection install failed for ${collection} after 8 attempts" >&2; \
                exit 1; \
            fi; \
            echo "ansible-galaxy timed out for ${collection}, retrying in 15s (attempt ${attempt}/8) ..."; \
            sleep 15; \
        done; \
    done \
    && \
    rm -f /tmp/requirements.txt /tmp/ansible-requirements.yml \
    && \
    rm -rf /tmp/* /var/tmp/*

COPY token.sh /token.sh
COPY app_token.sh /app_token.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /token.sh /app_token.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]
