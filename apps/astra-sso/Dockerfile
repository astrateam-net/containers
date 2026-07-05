# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Astra SSO — authentik server, patched. Two overlays on the stock upstream image
# (VERSION supplied by docker-bake.hcl):
#
#   1. cap_net_bind_service on the server binary, so the non-root (uid 1000)
#      process can bind privileged ports (80/443) directly — no root, no forwarder.
#
#   2. Enterprise unlock: force LicenseUsageStatus.is_valid -> True. Every enterprise
#      gate (EnterpriseRequiredMixin, enterprise_action, EnterpriseConfig.check_enabled,
#      the license middleware) funnels through this ONE property, so this single edit
#      unlocks all Enterprise features — notably the Source stage the HRD auth flow needs
#      (see astrateam-control-plane terraform/authentik/policies/flow_hrd.tf).
#
# Renamed from plain `authentik` on purpose: this image bypasses licensing and MUST NOT
# be confused with the stock upstream image. The cap-only overlay stays as `authentik`.
#
# PER-BUMP VERIFICATION (do on every VERSION bump): the grep-guard below fails the build
# loudly if upstream renames/moves `is_valid`, so a silent no-op can never ship. If the
# build fails at step 2, re-locate the license gate in authentik/enterprise/models.py.

ARG VERSION

FROM ghcr.io/goauthentik/server:${VERSION}

USER root

# 1. privileged-port bind capability
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin \
 && setcap cap_net_bind_service+ep /usr/bin/authentik-server \
 && apt-get purge -y libcap2-bin && rm -rf /var/lib/apt/lists/*

# 2. Enterprise unlock — single seam: LicenseUsageStatus.is_valid -> True.
#    grep-guard BEFORE sed => the build fails loudly if the gated line ever moves.
RUN set -eux; f=/authentik/enterprise/models.py; \
    test -f "$f"; \
    grep -q 'return self in \[LicenseUsageStatus.VALID, LicenseUsageStatus.EXPIRY_SOON\]' "$f"; \
    sed -i 's/return self in \[LicenseUsageStatus.VALID, LicenseUsageStatus.EXPIRY_SOON\]/return True/' "$f"; \
    grep -A2 'def is_valid' "$f" | grep -q 'return True'; \
    rm -f /authentik/enterprise/__pycache__/models*.pyc

USER 1000
