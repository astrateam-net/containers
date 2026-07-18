#!/usr/bin/env python3
"""Sign a license JWT for a cluster.

Usage: tokens.py --key private.pem --cluster <name> \
                 [--product P] [--company C] [--slug S] [--expires YYYY-MM-DD] [--out license.jwt]
"""
import argparse
import datetime
import time

import jwt  # type: ignore
from cryptography.hazmat.primitives.serialization import (  # type: ignore
    Encoding,
    PublicFormat,
    load_pem_private_key,
)

PRODUCT = "grafana-enterprise-logs"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    ap.add_argument("--cluster", required=True)
    ap.add_argument("--company", default="Enterprise")
    ap.add_argument("--slug", default="enterprise")
    ap.add_argument("--product", default=PRODUCT)
    ap.add_argument("--expires", default="2050-01-01")
    ap.add_argument("--out", default="license.jwt")
    a = ap.parse_args()

    with open(a.key, "rb") as f:
        priv_pem = f.read()
    priv = load_pem_private_key(priv_pem, password=None)

    y, m, d = map(int, a.expires.split("-"))
    now = int(time.time())
    exp = int(time.mktime(datetime.date(y, m, d).timetuple()))

    claims = {
        "sub": a.cluster, "iss": "Grafana Labs",
        "iat": now, "nbf": now - 60, "exp": exp, "lexp": exp,
        "lid": "1", "company": a.company, "slug": a.slug,
        "owner": {"name": a.company, "email": "licensing@example.com"},
        "prod": [a.product],
    }
    token = jwt.encode(claims, priv_pem, algorithm="RS512",
                       headers={"kid": "1", "typ": "JWT"})

    pub_pem = priv.public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    chk = jwt.decode(token, pub_pem, algorithms=["RS512"],
                     options={"verify_aud": False})
    assert chk["sub"] == a.cluster
    assert chk["prod"] == [a.product]

    with open(a.out, "w") as f:
        f.write(token)
    print(f"license: OK - {a.out} ({len(token)} bytes)")


if __name__ == "__main__":
    main()
