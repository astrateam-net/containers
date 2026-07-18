#!/usr/bin/env python3
"""Rewrite the kid=1 RSA JWK modulus in a binary to a public key's modulus.

Usage: agent.py <binary_in> <public_pem> <binary_out>
"""
import base64
import json
import re
import sys

from cryptography.hazmat.primitives.serialization import (  # type: ignore
    load_pem_public_key,
)

TARGET_KID = "1"


def die(msg):
    sys.exit(f"agent: FAIL: {msg}")


def b64u(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def find_target_jwk(data):
    for m in re.finditer(rb'\{"kty":"RSA', data):
        i = m.start()
        depth, j, end = 0, i, None
        while j < len(data) and j < i + 5000:
            c = data[j]
            if c == 0x7B:
                depth += 1
            elif c == 0x7D:
                depth -= 1
                if depth == 0:
                    end = j + 1
                    break
            j += 1
        if end is None:
            continue
        try:
            obj = json.loads(bytes(data[i:end]))
        except ValueError:
            continue
        if str(obj.get("kid")) == TARGET_KID and "n" in obj:
            return i, end, obj["n"]
    return None


def main():
    if len(sys.argv) != 4:
        die("usage: agent.py <binary_in> <public_pem> <binary_out>")
    src, pem_path, dst = sys.argv[1:4]

    with open(pem_path, "rb") as f:
        pub = load_pem_public_key(f.read())
    n = pub.public_numbers().n
    our_n = b64u(n.to_bytes((n.bit_length() + 7) // 8, "big"))

    with open(src, "rb") as f:
        data = bytearray(f.read())
    orig_size = len(data)

    target = find_target_jwk(data)
    if target is None:
        die(f"kid={TARGET_KID} JWK not found")
    obj_start, obj_end, their_n = target

    if len(their_n) != len(our_n):
        die(f"modulus length mismatch: {len(their_n)} vs {len(our_n)}")

    needle = ('"n":"' + their_n + '"').encode()
    off = data.find(needle, obj_start, obj_end)
    if off < 0:
        die("modulus bytes not found")
    val_off = off + len(b'"n":"')
    data[val_off:val_off + len(our_n)] = our_n.encode()

    if len(data) != orig_size:
        die("size changed")
    if our_n.encode() not in data:
        die("new modulus missing")
    if their_n.encode() in data:
        die("old modulus still present")

    with open(dst, "wb") as f:
        f.write(data)
    print(f"agent: OK @0x{val_off:x} (len={len(our_n)}, size={orig_size})")


if __name__ == "__main__":
    main()
