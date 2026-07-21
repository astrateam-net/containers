#!/usr/bin/env python3
"""Build-stage binary rewriter. Usage: agent.py <in> <out>."""
import shutil
import sys

BASE = 0x400000

EDITS = [
    (0x06C19966, "554889e54883ec08", "b001c39090909090"),
    (0x06C19906, "554889e54883ec08", "31c0c39090909090"),
    (0x06C199C0, "4885c90f8eab000000", "e9af00000090909090"),
    (0x0300098A, "554889e54883ec40", "b001c39090909090"),
    (0x06DFCF9B, "740eb817000000", "eb0eb817000000"),
]


def main(src, dst):
    shutil.copyfile(src, dst)
    with open(dst, "r+b") as f:
        for i, (va, a_hex, b_hex) in enumerate(EDITS):
            a, b = bytes.fromhex(a_hex), bytes.fromhex(b_hex)
            if len(a) != len(b):
                print(f"FAIL {i}: length", file=sys.stderr)
                return 1
            off = va - BASE
            f.seek(off)
            if f.read(len(a)) != a:
                print(f"FAIL {i} @ {va:#x}", file=sys.stderr)
                return 1
            f.seek(off)
            f.write(b)
            print(f"ok {i} @ {va:#x}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: agent.py <in> <out>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
