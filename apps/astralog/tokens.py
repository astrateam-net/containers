#!/usr/bin/env python3
"""astralog - offline signer for a Grafana Enterprise Logs (GEL) license.

The astralog image trusts our public key (baked into the enterprise-logs binary
by agent.py), so a license signed with the matching private key validates against
100% stock GEL code - "found a valid license", the management API starts, all
enterprise features on.

This is a pure, self-contained signing utility. It takes a private key and a
cluster name and emits a signed license JWT. Where the private key comes from,
where the emitted license is stored, and how it reaches a running cluster are
deployment concerns owned elsewhere (control-plane 1Password) - none of that
belongs to image building.

The `sub` claim MUST equal the cluster's `-cluster-name` (GEL reads the cluster
from `sub`). The claims are FLAT and top-level - there is NO `details` wrapper and
NO `subscriptions` objects (those are ignored). The two load-bearing fields:
  * `lexp`  int64 unix seconds - LICENSE expiration. Without it GEL reports
            "license expired at 1970-01-01" (time.Unix(0,0) on an unset int64).
  * `prod`  []license.Product where license.Product is a STRING type, i.e. a plain
            list of product-id strings: ["grafana-enterprise-logs"]. Empty/missing
            -> "does not have at least one valid subscription".

The signing key (kid=1) is byte-identical to Grafana Enterprise's, so this reuses
the astragraf keypair (see apps/astragraf). Version-independent.

Usage:
  tokens.py --key private.pem --cluster astralogs \
            [--company AstraTeam] [--expires 2050-01-01] [--out license.jwt]
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
    ap.add_argument("--key", required=True, help="RSA-4096 private key PEM")
    ap.add_argument("--cluster", required=True,
                    help="cluster name == subject == -cluster-name")
    ap.add_argument("--company", default="Enterprise")
    ap.add_argument("--slug", default="enterprise")
    ap.add_argument("--product", default=PRODUCT)
    ap.add_argument("--expires", default="2050-01-01", help="YYYY-MM-DD")
    ap.add_argument("--out", default="license.jwt")
    a = ap.parse_args()

    with open(a.key, "rb") as f:
        priv_pem = f.read()
    priv = load_pem_private_key(priv_pem, password=None)

    y, m, d = map(int, a.expires.split("-"))
    now = int(time.time())
    exp = int(time.mktime(datetime.date(y, m, d).timetuple()))

    # FLAT, top-level claims - mirrors astragraf's Grafana license.
    claims = {
        "sub": a.cluster,                 # cluster name (GEL reads cluster from sub)
        "iss": "Grafana Labs",
        "iat": now, "nbf": now - 60,
        "exp": exp,                       # JWT expiration, int64 unix
        "lexp": exp,                      # LICENSE expiration, int64 unix - essential
        "lid": "1",                       # license id
        "company": a.company,
        "slug": a.slug,
        "owner": {"name": a.company, "email": "licensing@example.com"},
        "prod": [a.product],              # []license.Product == string list
    }
    token = jwt.encode(claims, priv_pem, algorithm="RS512",
                       headers={"kid": "1", "typ": "JWT"})

    # self-verify against our own public half (mirrors the running cluster)
    pub_pem = priv.public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    chk = jwt.decode(token, pub_pem, algorithms=["RS512"],
                     options={"verify_aud": False})
    assert chk["sub"] == a.cluster
    assert chk["prod"] == [a.product]
    assert chk["lexp"] == exp

    with open(a.out, "w") as f:
        f.write(token)
    print(f"license: OK - {a.out} ({len(token)} bytes), "
          f"cluster={a.cluster}, product={a.product}, expires={a.expires}")


if __name__ == "__main__":
    main()
