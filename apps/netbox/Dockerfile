# syntax=docker/dockerfile:1

# NetBox = official netbox-docker base + carried plugins (netbox-acls, netbox-branching) + boto3
# for Cloudflare R2 media. Consumed by the tower repo (stacks/tools/netbox). Versions: docker-bake.hcl.
ARG VERSION=4.6.4
ARG NETBOX_DOCKER_VERSION=5.0.1
FROM netboxcommunity/netbox:v${VERSION}-${NETBOX_DOCKER_VERSION}

ARG NETBOX_ACLS_VERSION
ARG NETBOX_BRANCHING_VERSION

RUN /usr/local/bin/uv pip install \
      "netbox-acls==${NETBOX_ACLS_VERSION}" \
      "netboxlabs-netbox-branching==${NETBOX_BRANCHING_VERSION}" \
      boto3

# Bake the plugin-enable list (also wraps DATABASES for branching) so collectstatic gathers plugin
# static assets. The SECRET_KEY here is build-time only; the real key is a Docker secret at runtime.
COPY configuration/plugins.py /etc/netbox/config/plugins.py
RUN DEBUG="true" \
    SECRET_KEY="build-time-only-dummy-not-used-at-runtime-0000000000" \
    /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py collectstatic --no-input
