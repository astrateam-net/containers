#!/usr/bin/env python3
"""Sign a license token for a Grafana instance.

Usage: tokens.py --key private.pem --root-url https://grafana.example.com/ \
                 [--company C] [--slug S] [--users N] [--expires YYYY-MM-DD] [--out license.jwt]
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", required=True)
    ap.add_argument("--root-url", required=True)
    ap.add_argument("--company", default="Enterprise")
    ap.add_argument("--slug", default="enterprise")
    ap.add_argument("--users", type=int, default=100000)
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
        "sub": a.root_url, "iss": "https://grafana.com",
        "iat": now, "nbf": now - 60, "exp": exp, "lexp": exp,
        "lid": "1", "license_id": "1", "prod": ["grafana-enterprise"],
        "company": a.company, "account": a.company, "slug": a.slug,
        "name": f"{a.company} Enterprise", "limit_by": "users",
        "included_users": a.users, "included_admins": a.users,
        "included_viewers": a.users, "max_concurrent_user_sessions": 0,
        "license_type": "enterprise",
    }
    token = jwt.encode(claims, priv_pem, algorithm="RS512",
                       headers={"kid": "1", "typ": "JWT"})

    pub_pem = priv.public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    chk = jwt.decode(token, pub_pem, algorithms=["RS512"],
                     options={"verify_aud": False})
    assert chk["sub"] == a.root_url
    assert chk["prod"] == ["grafana-enterprise"]

    with open(a.out, "w") as f:
        f.write(token)
    print(f"token: OK - {a.out} ({len(token)} bytes)")


if __name__ == "__main__":
    main()
