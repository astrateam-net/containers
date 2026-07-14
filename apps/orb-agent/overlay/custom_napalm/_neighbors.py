# Copyright 2026 AstraTeam
"""Parse MikroTik RouterOS `/ip neighbor print detail` into physical LLDP links.

RouterOS neighbour discovery merges CDP, LLDP and MNDP into one table. Only an
LLDP neighbour on a physical, point-to-point port describes a real cable; the
rest is noise:

  * MNDP/CDP mgmt-plane adjacency — every device on the management VLAN sees
    every other one on its bridge SVI (`interface=br0.115`, `discovered-by=cdp,mndp`).
    Ingesting those would draw a cable between every pair of devices.
  * Shared-segment / uplink trunks — one physical port with many neighbours behind
    a downstream switch. Not a point-to-point cable.

This module distils the raw table down to the clean point-to-point LLDP links and
returns them in NAPALM's ``get_lldp_neighbors_detail()`` shape so the translator
stays vendor-neutral.

Parsing is driver-local regex (not an ntc-template) on purpose: RouterOS 7 detail
output wraps each record across several indented lines and quotes multi-word values
across line breaks, which the bundled TextFSM template does not survive — the same
reason this driver already regex-parses interface / vlan detail.
"""

import re

# A record starts with a bare row index near column 0 (" 0 interface=..."). Wrapped
# continuation lines are indented and never start with a bare digit, so splitting on
# the index anchor slices the blob into one record per neighbour.
_RECORD_ANCHOR = re.compile(r"(?m)^\s*\d+\s")

_INTERFACE_RE = re.compile(r"(?<![\w-])interface=(?P<v>\S+)")
_INTERFACE_NAME_RE = re.compile(r'interface-name="(?P<v>[^"]*)"')
_IDENTITY_RE = re.compile(r'identity="(?P<v>[^"]*)"')
_MAC_RE = re.compile(r"mac-address=(?P<v>[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})")
_DISCOVERED_BY_RE = re.compile(r"discovered-by=(?P<v>\S+)")

# Local names that are never one end of a cable: the bridge itself (br0, bridge1)
# and any VLAN / bridge sub-interface (contains a dot, e.g. br0.115 — the mgmt SVI).
_BRIDGE_RE = re.compile(r"^(?:bridge|br)\d*$", re.IGNORECASE)


def _first_token(value: str) -> str:
    """RouterOS lists the physical port first: `sfp-sfpplus1,br0` -> `sfp-sfpplus1`."""
    return value.split(",", 1)[0].strip()


def _remote_port(interface_name: str) -> str | None:
    """Return the remote physical port from a RouterOS `interface-name` value.

    `interface-name` is `<remote-bridge>/<remote-port>` for an LLDP neighbour
    (e.g. `br0/sfp-sfpplus1` -> `sfp-sfpplus1`). Returns None when there is no `/`
    (the neighbour reported only a bridge / SVI such as `br0.115` — an MNDP mgmt
    adjacency, not a cable) or the remote end is itself a bridge / VLAN.
    """
    if "/" not in interface_name:
        return None
    remote = interface_name.rsplit("/", 1)[-1].strip()
    if not remote or "." in remote or _BRIDGE_RE.match(remote):
        return None
    return remote


def _is_physical_local(port: str, local_interfaces: set[str]) -> bool:
    """Accept a local port only if it is a real physical interface, not a bridge/VLAN."""
    if not port or "." in port or _BRIDGE_RE.match(port):
        return False
    # When the device's interface list is known, require membership so a parse slip
    # can't invent a port. When unknown (empty set), fall back to the name shape above.
    return port in local_interfaces if local_interfaces else True


def parse_neighbors(
    output: str, local_interfaces: set[str] | None = None
) -> dict[str, list[dict]]:
    """Return ``{local_port: [neighbor]}`` for clean point-to-point LLDP links only.

    Neighbour dicts use NAPALM's ``get_lldp_neighbors_detail()`` keys. A local port
    is emitted only when it has EXACTLY ONE qualifying LLDP neighbour (point-to-point);
    ports with two or more are a shared segment / trunk and are dropped entirely.
    """
    if not output:
        return {}
    local_interfaces = local_interfaces or set()

    # Collect candidates per local port first so point-to-point can be enforced.
    by_port: dict[str, list[dict]] = {}
    starts = [m.start() for m in _RECORD_ANCHOR.finditer(output)]
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(output)
        block = output[start:end]

        # Only LLDP describes a physical port. Drop cdp/mndp-only records — that
        # removes both the mgmt-VLAN mesh and non-LLDP endpoints (e.g. cAP APs).
        m_disc = _DISCOVERED_BY_RE.search(block)
        if not m_disc or "lldp" not in m_disc.group("v").split(","):
            continue

        m_if = _INTERFACE_RE.search(block)
        if not m_if:
            continue
        local = _first_token(m_if.group("v"))
        if not _is_physical_local(local, local_interfaces):
            continue

        m_ident = _IDENTITY_RE.search(block)
        remote_device = m_ident.group("v").strip() if m_ident else ""
        if not remote_device:
            continue

        m_ifn = _INTERFACE_NAME_RE.search(block)
        remote_port = _remote_port(m_ifn.group("v")) if m_ifn else None
        if not remote_port:
            continue

        m_mac = _MAC_RE.search(block)
        by_port.setdefault(local, []).append(
            {
                "remote_system_name": remote_device,
                "remote_port": remote_port,
                "remote_chassis_id": m_mac.group("v") if m_mac else "",
                "remote_port_description": "",
                "parent_interface": "",
            }
        )

    # Keep only point-to-point ports (exactly one LLDP neighbour).
    return {port: nbrs for port, nbrs in by_port.items() if len(nbrs) == 1}
