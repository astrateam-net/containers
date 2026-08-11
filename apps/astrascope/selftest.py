#!/usr/bin/env python3
import marshal
import os
import sys

CODE = "/code"
PYC = f"{CODE}/smith-backend/app/license/validation.pyc"
GOBINS = [
    f"{CODE}/smith-go/{b}"
    for b in ("smith-go", "asynq-worker", "smith-intelligence")
]
OURKEY = open("/tmp/astrascope-public.pem", "rb").read().strip()


def fail(msg):
    sys.exit(f"ASTRASCOPE SELFTEST FAIL: {msg}")


def original_key():
    with open(PYC, "rb") as f:
        f.read(16)
        code = marshal.load(f)
    keys = [
        c for c in code.co_consts
        if isinstance(c, str) and "PUBLIC KEY" in c
    ]
    if not keys:
        fail("LICENSE_PUBLIC_KEY const gone from validation.pyc")
    names = {c.co_name for c in code.co_consts if hasattr(c, "co_name")}
    for fn in ("decode_license_key", "get_license_status"):
        if fn not in names:
            fail(f"{fn} gone from validation.pyc")
    return keys[0].strip().encode()


def main():
    orig = original_key()
    if len(orig) != len(OURKEY):
        fail(f"key length {len(orig)} != {len(OURKEY)}")

    for path in [PYC, *GOBINS]:
        name = os.path.basename(path)
        data = open(path, "rb").read()
        if path in GOBINS and b"DecodeLicenseJWT" not in data:
            fail(f"DecodeLicenseJWT gone from {name}")
        count = data.count(orig)
        if count < 1:
            fail(f"original key not found in {name}")
        patched = data.replace(orig, OURKEY)
        if len(patched) != len(data):
            fail(f"length drift in {name}")
        with open(path, "wb") as f:
            f.write(patched)
        check = open(path, "rb").read()
        if OURKEY not in check or orig in check:
            fail(f"swap failed in {name}")
        print(f"  ok  {name} ({count}x)")

    with open(PYC, "rb") as f:
        f.read(16)
        marshal.load(f)
    print("ASTRASCOPE OK")


if __name__ == "__main__":
    main()
