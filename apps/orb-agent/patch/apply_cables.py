#!/usr/bin/env python3
"""Wire LLDP-neighbour -> NetBox Cable discovery into the installed device-discovery.

Additive modules are dropped in by the Dockerfile (device_discovery/cable.py,
custom_napalm/_neighbors.py). This script makes the four count-verified in-place
edits that connect them to the pipeline:

  1. custom_napalm/mikrotik_routeros.py  — import parse_neighbors + add the
     get_lldp_neighbors_detail() getter.
  2. device_discovery/policy/models.py   — add discover_cables + cable_peer_pattern
     to the Options model.
  3. device_discovery/policy/runner.py   — dispatch _collect_neighbors() alongside
     the other optional getters.
  4. device_discovery/translate.py       — import build_cable_entities + emit cables
     in translate_data().

Every edit is anchored on exact upstream text and asserts EXACTLY ONE match. If an
upstream version bump drifts an anchor, the build FAILS here instead of shipping a
half-wired image (same discipline as patch/apply.py for the SNMP fix).

Usage: apply_cables.py <device_discovery_dir> <custom_napalm_dir>
"""

import sys
from pathlib import Path


def patch(path: Path, anchor: str, replacement: str, *, label: str) -> None:
    """Replace the single occurrence of `anchor` with `replacement`, or exit non-zero."""
    src = path.read_text()
    n = src.count(anchor)
    if n != 1:
        sys.exit(
            f"apply_cables.py: anchor drift in {label} ({path.name}): "
            f"expected 1 match, found {n}. Re-verify against this upstream version."
        )
    path.write_text(src.replace(anchor, replacement, 1))
    print(f"apply_cables.py: patched {label} ({path.name}).")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: apply_cables.py <device_discovery_dir> <custom_napalm_dir>")
    dd = Path(sys.argv[1])
    cn = Path(sys.argv[2])

    # --- 1. MikroTik driver: import + getter -------------------------------------
    driver = cn / "mikrotik_routeros.py"
    patch(
        driver,
        "from ntc_templates.parse import parse_output\n",
        "from ntc_templates.parse import parse_output\n"
        "from custom_napalm._neighbors import parse_neighbors\n",
        label="driver import",
    )
    patch(
        driver,
        "        try:\n"
        "            return _parse_vlans(raw)\n"
        "        except Exception:\n"
        '            logger.debug("Failed to parse \'interface vlan print\'", exc_info=True)\n'
        "            return {}\n",
        "        try:\n"
        "            return _parse_vlans(raw)\n"
        "        except Exception:\n"
        '            logger.debug("Failed to parse \'interface vlan print\'", exc_info=True)\n'
        "            return {}\n"
        "\n"
        '    def get_lldp_neighbors_detail(self, interface: str = "") -> dict:\n'
        '        """\n'
        "        Return point-to-point LLDP neighbours for physical-cable discovery.\n"
        "\n"
        "        Parses 'ip neighbor print detail' with driver-local regex (the RouterOS 7\n"
        "        multi-line detail output breaks the ntc-template) and keeps only LLDP\n"
        "        neighbours on a physical, single-neighbour port. See custom_napalm._neighbors.\n"
        "        The optional 'interface' arg (NAPALM signature) narrows to one local port.\n"
        '        """\n'
        '        raw = self.device.send_command("ip neighbor print detail")\n'
        "        if not raw:\n"
        "            return {}\n"
        "        try:\n"
        '            local_ifaces = {row["name"] for row in self._interfaces_detail()}\n'
        "            result = parse_neighbors(raw, local_interfaces=local_ifaces)\n"
        "        except Exception:\n"
        '            logger.debug("Failed to parse \'ip neighbor print detail\'", exc_info=True)\n'
        "            return {}\n"
        "        if interface:\n"
        "            return {interface: result[interface]} if interface in result else {}\n"
        "        return result\n",
        label="driver getter",
    )

    # --- 1b. Driver: stop clobbering SNMP interface descriptions -----------------
    # get_interfaces() hardcoded description="" — on the proto's `optional string
    # description` an empty string is a PRESENT value, so Diode overwrites the
    # description snmp_discovery set from ifAlias (the RouterOS port comment).
    # Drop the key: the field goes out absent (None), Diode PATCH leaves the
    # existing value untouched, and snmp_discovery stays the single owner of
    # interface descriptions. No more device-vs-snmp clobber cycle.
    patch(
        driver,
        "            result[name] = {\n"
        '                "is_up": row["is_up"],\n'
        '                "is_enabled": row["is_enabled"],\n'
        '                "description": "",\n'
        '                "last_flapped": -1.0,\n'
        '                "mtu": row["mtu"],\n'
        '                "speed": -1.0,\n'
        '                "mac_address": row["mac_address"],\n'
        "            }\n",
        "            result[name] = {\n"
        '                "is_up": row["is_up"],\n'
        '                "is_enabled": row["is_enabled"],\n'
        '                "last_flapped": -1.0,\n'
        '                "mtu": row["mtu"],\n'
        '                "speed": -1.0,\n'
        '                "mac_address": row["mac_address"],\n'
        "            }\n",
        label="driver: drop empty description (no SNMP clobber)",
    )

    # --- 2. Options model: discover_cables + cable_peer_pattern -------------------
    models = dd / "policy" / "models.py"
    patch(
        models,
        "\n\n\nclass Config(BaseModel):",
        "\n"
        "    discover_cables: bool = Field(\n"
        "        default=False,\n"
        "        description=(\n"
        '            "Discover physical cables from the device\'s LLDP neighbours via "\n'
        '            "the driver\'s get_lldp_neighbors_detail() and emit NetBox Cable "\n'
        '            "entities for point-to-point links. Default False."\n'
        "        ),\n"
        "    )\n"
        "    cable_peer_pattern: str | None = Field(\n"
        "        default=None,\n"
        "        description=(\n"
        '            "Optional regex; when set, a discovered cable is emitted only if "\n'
        '            "the remote peer name matches it. Use to restrict cabling to the "\n'
        '            "managed fabric (e.g. \'^HQ-\') and avoid stub devices for servers / "\n'
        '            "NAS that also speak LLDP. Default None (all peers)."\n'
        "        ),\n"
        "    )\n"
        "\n\nclass Config(BaseModel):",
        label="Options fields",
    )

    # --- 3. Runner: dispatch _collect_neighbors ----------------------------------
    runner = dd / "policy" / "runner.py"
    patch(
        runner,
        "            self._collect_network_instances(config, device, data, sanitized_hostname)\n",
        "            self._collect_network_instances(config, device, data, sanitized_hostname)\n"
        "            self._collect_neighbors(config, device, data, sanitized_hostname)\n",
        label="runner dispatch call",
    )
    patch(
        runner,
        "    def run_scan(\n",
        "    def _collect_neighbors(\n"
        "        self,\n"
        "        config: Config,\n"
        "        device: Any,\n"
        "        data: dict,\n"
        "        sanitized_hostname: str,\n"
        "    ) -> None:\n"
        '        """\n'
        "        Call the driver's get_lldp_neighbors_detail() when discover_cables is on.\n"
        "\n"
        "        Gated by config.options.discover_cables (False is a no-op). Drivers\n"
        "        without the getter (or NAPALM's NotImplementedError base) land in the\n"
        "        except branch: discovery continues without cable data.\n"
        '        """\n'
        "        if not (config.options and getattr(config.options, \"discover_cables\", False)):\n"
        "            return\n"
        '        get_neighbors = getattr(device, "get_lldp_neighbors_detail", None)\n'
        "        if not callable(get_neighbors):\n"
        "            return\n"
        "        try:\n"
        '            data["lldp_neighbors_detail"] = get_neighbors()\n'
        "        except Exception as e:\n"
        "            logger.warning(\n"
        '                f"Policy {self.name}, Hostname {sanitized_hostname}: "\n'
        '                f"Error getting LLDP neighbors: {e}. "\n'
        '                "Continuing without cable data."\n'
        "            )\n"
        "\n"
        "    def run_scan(\n",
        label="runner method",
    )

    # --- 4. translate_data: import + emit cables ---------------------------------
    translate = dd / "translate.py"
    patch(
        translate,
        "from device_discovery.vrf import build_discovered_vrfs\n",
        "from device_discovery.vrf import build_discovered_vrfs\n"
        "from device_discovery.cable import build_cable_entities\n",
        label="translate import",
    )
    patch(
        translate,
        '    _emit_vlans_and_stubs(entities, data.get("vlan"), defaults, new_stubs)\n'
        "    return entities\n",
        '    _emit_vlans_and_stubs(entities, data.get("vlan"), defaults, new_stubs)\n'
        "    entities.extend(build_cable_entities(data))\n"
        "    return entities\n",
        label="translate cable hook",
    )


if __name__ == "__main__":
    main()
