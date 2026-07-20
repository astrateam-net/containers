#!/usr/bin/env python3
"""Swap the license public key for ours.

Usage: patch.py <our_public_pem> <target_in> <target_out>

Handles two shapes:
  * a bare PEM file (the whole file IS the key) -> replaced with ours
  * a source file with the key embedded as a PEM literal -> only the PEM block
    is replaced, the rest is left byte-for-byte intact

Fails loud if the upstream key is not present at the target: a version bump that
rotates the key or moves the file breaks the build instead of silently shipping
an image that still trusts the upstream key.
"""
import sys

# Distinctive slice of the upstream RSA-4096 modulus (stable across releases).
# Its presence proves we are overwriting the real validator key, not a stray path.
OLD_ANCHOR = "o3G2lxK+FfE5h2b02JiCStkjopOte4yygDrSkEc8ns50"

BEGIN = "-----BEGIN PUBLIC KEY-----"
END = "-----END PUBLIC KEY-----"


def die(msg: str) -> None:
    sys.exit(f"patch: FAIL: {msg}")


def main() -> None:
    our_pem, target_in, target_out = sys.argv[1], sys.argv[2], sys.argv[3]
    our = open(our_pem, encoding="utf-8").read().strip()
    if BEGIN not in our or END not in our:
        die("our replacement is not a PEM public key")

    data = open(target_in, encoding="utf-8", errors="surrogateescape").read()
    if OLD_ANCHOR not in data:
        die(f"upstream key anchor not found in {target_in} — key rotated or path moved; re-verify unlock")

    if data.strip().startswith(BEGIN) and data.strip().endswith(END):
        out = our + "\n"  # bare PEM file
    else:
        i = data.index(BEGIN)
        j = data.index(END, i) + len(END)
        out = data[:i] + our + data[j:]  # embedded PEM literal

    if OLD_ANCHOR in out:
        die("old key still present after swap")

    open(target_out, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print(f"patch: ok {target_in} -> {target_out}")


main()
