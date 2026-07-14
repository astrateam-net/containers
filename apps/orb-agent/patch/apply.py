#!/usr/bin/env python3
"""Rewire Client.Walk onto tolerantWalkAll. Run from the snmp-discovery module root.

We keep it minimal (this one swap): the tolerant walk removes the only benign
cause of the "OID not increasing" abort, and leaving Host.Walk's fatal-on-error
contract intact keeps genuine timeouts loud (and the upstream test suite green).

The edit is count-verified: if the upstream anchor drifted on a version bump, we
exit non-zero and FAIL THE BUILD instead of shipping an unpatched binary.
"""
import re
import sys
from pathlib import Path

target = Path("snmp/snmp.go")
src = target.read_text()

src, n = re.subn(r"c\.WalkAll\(objectIDs\)", "tolerantWalkAll(c.GoSNMP, objectIDs)", src)
if n != 1:
    sys.exit(f"apply.py: anchor drift (c.WalkAll): expected 1 match, got {n}. "
             "Re-verify snmp/snmp.go against this patch.")

target.write_text(src)
print("apply.py: patched snmp/snmp.go (Client.Walk -> tolerantWalkAll).")
