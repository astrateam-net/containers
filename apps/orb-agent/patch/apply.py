#!/usr/bin/env python3
"""Make snmp-discovery's walk tolerate non-increasing OIDs. Run from the module root.

MikroTik RouterOS emits BRIDGE-MIB / Q-BRIDGE-MIB tables out of lexicographic
order, so gosnmp's strict WalkAll aborts the whole device crawl with "OID not
increasing". gosnmp already ships the fix as a flag — AppOpts["c"] — which is
exactly `snmpwalk -Cc`: it relaxes ONLY the increasing-OID check inside the stock
WalkAll and preserves everything else (the leaf-OID GET fallback that retrieves
scalar device fields like sysName/sysObjectID, subtree bounds, EndOfMib).

So the whole patch is: set c.AppOpts["c"]=true right before the existing
c.WalkAll(objectIDs) call in Client.Walk. No custom walk, no reimplementation —
that is what previously dropped the leaf-scalar retrieval. For well-behaved
(increasing) devices the flag is a no-op; it only relaxes the check MikroTik trips.

The edit is count-verified: if the upstream anchor drifted on a version bump, we
exit non-zero and FAIL THE BUILD instead of shipping an unpatched binary.
"""
import re
import sys
from pathlib import Path

target = Path("snmp/snmp.go")
src = target.read_text()

anchor = re.compile(r"([ \t]*)pdu, err := c\.WalkAll\(objectIDs\)")
if len(anchor.findall(src)) != 1:
    sys.exit("apply.py: anchor drift (c.WalkAll(objectIDs)): expected 1 match. "
             "Re-verify snmp/snmp.go against this patch.")

repl = (
    r"\1// AstraTeam: tolerate non-increasing OIDs (MikroTik RouterOS BRIDGE-MIB),"
    "\n\\1// equivalent to `snmpwalk -Cc`. Relaxes only gosnmp's increasing-OID"
    "\n\\1// check; WalkAll's leaf-GET fallback and subtree bounds are preserved."
    "\n\\1if c.AppOpts == nil {"
    "\n\\1\tc.AppOpts = map[string]any{}"
    "\n\\1}"
    "\n\\1c.AppOpts[\"c\"] = true"
    "\n\\1pdu, err := c.WalkAll(objectIDs)"
)
src = anchor.sub(repl, src, count=1)

target.write_text(src)
print("apply.py: patched snmp/snmp.go (WalkAll -> AppOpts[\"c\"] tolerant walk).")
