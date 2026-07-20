#!/usr/bin/env python3
"""Usage: patch.py <public_pem> <in> <out>"""
import sys

OLD_ANCHOR = "o3G2lxK+FfE5h2b02JiCStkjopOte4yygDrSkEc8ns50"
BEGIN = "-----BEGIN PUBLIC KEY-----"
END = "-----END PUBLIC KEY-----"


def die(msg: str) -> None:
    sys.exit(f"patch: FAIL: {msg}")


def main() -> None:
    pem, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    our = open(pem, encoding="utf-8").read().strip()
    data = open(src, encoding="utf-8", errors="surrogateescape").read()
    if OLD_ANCHOR not in data:
        die(f"anchor not found in {src}")
    if data.strip().startswith(BEGIN) and data.strip().endswith(END):
        out = our + "\n"
    else:
        i = data.index(BEGIN)
        j = data.index(END, i) + len(END)
        out = data[:i] + our + data[j:]
    if OLD_ANCHOR in out:
        die("anchor still present")
    open(dst, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print(f"patch: ok {src}")


main()
