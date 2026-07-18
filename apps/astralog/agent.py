#!/usr/bin/env python3
"""astragraf - build-time trust-root swap for the Grafana Enterprise binary.

Grafana Enterprise verifies its license JWT against a set of RSA public keys
compiled into the binary (`pkg/extensions/licensing.keySet`, embedded as JWK
JSON, keyed by `kid`). We overwrite the `kid=1` key's modulus with OUR public
modulus, in place and at equal length, so the binary trusts tokens we sign
with the matching private key (see token.py). 100% stock code paths.

This is the compiled-Go analogue of the astracode (GitLab EE) approach, where
the trust root was a file we bind-mounted; here it is baked into the binary,
so we rewrite it at build time instead.

FAIL-LOUD: every structural assumption is asserted. If upstream renames the
package, drops `kid=1`, or changes the key size, this exits non-zero and the
image build fails - a broken build never ships silently.

Usage: agent.py <grafana_in> <public_pem> <grafana_out>
"""
import base64
import json
import re
import sys

from cryptography.hazmat.primitives.serialization import (  # type: ignore
    load_pem_public_key,
)

# the kid we sign against; keySet also holds "2" and "AWS-1"
TARGET_KID = "1"


def die(msg):
    sys.exit(f"agent: FAIL: {msg}")


def b64u(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def find_target_jwk(data):
    """Return (start, end, n) for the embedded kid=TARGET_KID RSA JWK."""
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
        die("usage: agent.py <grafana_in> <public_pem> <grafana_out>")
    src, pem_path, dst = sys.argv[1:4]

    # our public modulus, base64url (JWK "n" form)
    with open(pem_path, "rb") as f:
        pub = load_pem_public_key(f.read())
    n = pub.public_numbers().n
    our_n = b64u(n.to_bytes((n.bit_length() + 7) // 8, "big"))

    with open(src, "rb") as f:
        data = bytearray(f.read())
    orig_size = len(data)

    # ANCHOR 1: the embedded kid=1 RSA JWK (keySet trust root) must exist.
    target = find_target_jwk(data)
    if target is None:
        die(f"kid={TARGET_KID} RSA JWK not found - upstream moved the "
            "trust root")
    obj_start, obj_end, their_n = target

    # ANCHOR 2: the slot must equal our modulus length (both RSA-4096), so we
    # rewrite in place without shifting any bytes.
    if len(their_n) != len(our_n):
        die(f"modulus length mismatch: upstream={len(their_n)} "
            f"ours={len(our_n)} (key size changed?)")

    # locate the exact `"n":"..."` bytes for kid=1 and overwrite the value
    needle = ('"n":"' + their_n + '"').encode()
    off = data.find(needle, obj_start, obj_end)
    if off < 0:
        die(f"could not locate kid={TARGET_KID} modulus bytes to rewrite")
    val_off = off + len(b'"n":"')
    data[val_off:val_off + len(our_n)] = our_n.encode()

    # ANCHOR 3: post-conditions - our key in, original key out, size unchanged.
    if len(data) != orig_size:
        die(f"binary size changed ({orig_size} -> {len(data)})")
    if our_n.encode() not in data:
        die("our modulus not present after rewrite")
    if their_n.encode() in data:
        die(f"original kid={TARGET_KID} modulus still present after rewrite")

    with open(dst, "wb") as f:
        f.write(data)
    print(f"agent: OK - kid={TARGET_KID} rewritten in place @0x{val_off:x} "
          f"(len={len(our_n)}, size={orig_size} unchanged)")


if __name__ == "__main__":
    main()
