# syntax=docker/dockerfile:1

FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client jq git curl && \
    rm -rf /var/lib/apt/lists/*

ARG ANSIBLE_CORE_VERSION
ARG PARAMIKO_VERSION
ARG ANSIBLE_LINT_VERSION

RUN pip install --no-cache-dir \
    ansible-core==${ANSIBLE_CORE_VERSION} \
    paramiko==${PARAMIKO_VERSION} \
    ansible-lint==${ANSIBLE_LINT_VERSION}

COPY ansible-requirements.yml /tmp/ansible-requirements.yml
RUN ansible-galaxy collection install \
    --timeout 180 \
    -r /tmp/ansible-requirements.yml \
    -p /usr/share/ansible/collections \
    && rm -f /tmp/ansible-requirements.yml

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["ansible", "--version"]
