#!/usr/bin/env python3
"""astragraf - offline signer for a Grafana Enterprise token.

The astragraf image trusts our public key (baked into the binary by agent.py),
so a token signed with the matching private key validates against 100% stock
Grafana code - status=Valid, edition=Enterprise, all features enabled.

This is a pure, self-contained signing utility. It takes a private key and a
root_url and emits a signed token. Where the private key comes from, where the
emitted token is stored, and how it reaches a running instance are deployment
concerns owned elsewhere - none of that belongs to image building.

The `sub` claim MUST equal the instance's server root_url (Grafana compares
them); a trailing slash is expected. The token is version-independent.

Usage:
  token.py --key private.pem --root-url https://grafana.example.com/ \
           [--company Example] [--out license.jwt]
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
    ap.add_argument("--key", required=True, help="RSA-4096 private key PEM")
    ap.add_argument("--root-url", required=True,
                    help="instance root_url == subject (trailing slash)")
    ap.add_argument("--company", default="Enterprise")
    ap.add_argument("--slug", default="enterprise")
    ap.add_argument("--users", type=int, default=100000)
    ap.add_argument("--expires", default="2050-01-01", help="YYYY-MM-DD")
    ap.add_argument("--out", default="license.jwt")
    a = ap.parse_args()

    with open(a.key, "rb") as f:
        priv_pem = f.read()
    priv = load_pem_private_key(priv_pem, password=None)

    y, m, d = map(int, a.expires.split("-"))
    now = int(time.time())
    exp = int(time.mktime(datetime.date(y, m, d).timetuple()))

    # NOTE: `status` is a TokenStatus int enum in Grafana - do NOT set it as a
    # string, or parsing fails ("cannot unmarshal string ... TokenStatus").
    # Grafana derives status from the other claims. Omit it.
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

    # self-verify against our own public half (mirrors the running instance)
    pub_pem = priv.public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    chk = jwt.decode(token, pub_pem, algorithms=["RS512"],
                     options={"verify_aud": False})
    assert chk["sub"] == a.root_url
    assert chk["prod"] == ["grafana-enterprise"]

    with open(a.out, "w") as f:
        f.write(token)
    print(f"token: OK - {a.out} ({len(token)} bytes), "
          f"sub={a.root_url}, expires={a.expires}")


if __name__ == "__main__":
    main()
