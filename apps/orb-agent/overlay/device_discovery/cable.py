#!/usr/bin/env python
# Copyright 2026 AstraTeam
"""Build NetBox Cable entities from discovered LLDP neighbours.

Consumes the point-to-point LLDP links a driver's ``get_lldp_neighbors_detail()``
produced (see custom_napalm/_neighbors.py for the MikroTik producer) and emits one
Diode ``Cable`` per link, connecting the local interface to the remote interface.

Gated by the ``discover_cables`` option. An optional ``cable_peer_pattern`` regex
restricts which remote peers are cabled — set it to the managed-switch naming (e.g.
``^HQ-``) to keep the fabric clean and avoid creating stub devices for servers /
NAS that also speak LLDP.

Direction is canonicalised (the two endpoints are sorted) so BOTH devices of a link
emit an identical Cable: the far end's own discovery run produces the same a/b
terminations, so Diode reconciles the pair to a single cable instead of flapping.
"""

import logging
import re

from netboxlabs.diode.sdk.ingester import (
    Cable,
    Device,
    Entity,
    GenericObject,
    Interface,
    Site,
)

from device_discovery.policy.models import Defaults, Options

logger = logging.getLogger(__name__)

_UNDEFINED = "undefined"


def _site_name(defaults: Defaults) -> str | None:
    site = getattr(defaults, "site", None)
    if not site or site == _UNDEFINED:
        return None
    return site


def _termination(device_name: str, port: str, site: str | None) -> GenericObject:
    """A cable end: the interface (by name) on its device (by name + site)."""
    device = (
        Device(name=device_name, site=Site(name=site))
        if site
        else Device(name=device_name)
    )
    return GenericObject(object_interface=Interface(device=device, name=port))


def build_cable_entities(data: dict) -> list[Entity]:
    """Translate discovered LLDP neighbours into Diode Cable entities.

    Returns [] unless ``discover_cables`` is set and the driver produced
    ``lldp_neighbors_detail``. Emits one ``Cable(status="connected")`` per
    point-to-point link, terminations canonicalised for cross-device idempotency,
    peers filtered by the optional ``cable_peer_pattern``.
    """
    options = data.get("options") or Options()
    if not getattr(options, "discover_cables", False):
        return []

    neighbors = data.get("lldp_neighbors_detail") or {}
    if not neighbors:
        return []

    device_info = data.get("device") or {}
    local_device = device_info.get("hostname")
    if not local_device:
        return []

    peer_pattern = getattr(options, "cable_peer_pattern", None)
    peer_re = re.compile(peer_pattern) if peer_pattern else None

    defaults = data.get("defaults") or Defaults()
    site = _site_name(defaults)
    tags = list(getattr(defaults, "tags", None) or [])

    entities: list[Entity] = []
    seen: set[tuple] = set()
    for local_port, nbrs in neighbors.items():
        for nbr in nbrs:
            remote_device = nbr.get("remote_system_name")
            remote_port = nbr.get("remote_port")
            if not remote_device or not remote_port:
                continue
            if peer_re and not peer_re.search(remote_device):
                logger.debug("cable: skip peer %s (no pattern match)", remote_device)
                continue

            # Canonical direction: sort the two (device, port) ends so the far
            # side's run emits an identical Cable -> Diode dedups to one.
            a_end, b_end = sorted(
                [(local_device, local_port), (remote_device, remote_port)]
            )
            key = (a_end, b_end)
            if key in seen:
                continue
            seen.add(key)

            entities.append(
                Entity(
                    cable=Cable(
                        a_terminations=[_termination(a_end[0], a_end[1], site)],
                        b_terminations=[_termination(b_end[0], b_end[1], site)],
                        status="connected",
                        tags=tags or None,
                    )
                )
            )
            logger.debug(
                "cable: %s:%s <-> %s:%s", a_end[0], a_end[1], b_end[0], b_end[1]
            )
    return entities
