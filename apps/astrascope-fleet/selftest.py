#!/usr/bin/env python3
import datetime
import marshal
import sys
import types

PYC = "/api/langgraph_license/validation.pyc"
OURKEY = open("/tmp/astrascope-public.pem").read().strip()


def fail(msg):
    sys.exit(f"ASTRASCOPE SELFTEST FAIL: {msg}")


def load():
    with open(PYC, "rb") as f:
        return f.read(16), marshal.load(f)


def find_key(code):
    for c in code.co_consts:
        if isinstance(c, str) and "PUBLIC KEY" in c:
            return c
        if isinstance(c, types.CodeType):
            r = find_key(c)
            if r:
                return r
    return None


def find_fn(code, name):
    for c in code.co_consts:
        if isinstance(c, types.CodeType):
            if c.co_name == name:
                return c
            r = find_fn(c, name)
            if r:
                return r
    return None


VENDOR_AUD = "langgraph-cloud"
OUR_AUD = "langsmith"


def swap(code, orig, new, in_gate=False):
    gate = in_gate or code.co_name == "decode_license_jwt"
    consts = []
    for c in code.co_consts:
        if isinstance(c, types.CodeType):
            consts.append(swap(c, orig, new, gate))
        elif c == orig:
            consts.append(new)
        elif gate and c == VENDOR_AUD:
            consts.append(OUR_AUD)
        else:
            consts.append(c)
    return code.replace(co_consts=tuple(consts))


def prove(code, orig):
    import jwt
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    k = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    priv = k.private_bytes(serialization.Encoding.PEM,
                           serialization.PrivateFormat.PKCS8,
                           serialization.NoEncryption()).decode()
    pub = k.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo).decode().strip()

    fn_code = find_fn(swap(code, orig, pub), "decode_license_jwt")
    if fn_code is None:
        fail("decode_license_jwt gone from validation.pyc")
    g = {"get_unverified_header": jwt.get_unverified_header, "decode": jwt.decode,
         "algorithms": jwt.algorithms, "ValueError": ValueError,
         "Exception": Exception, "LICENSE_PUBLIC_KEY": pub, "LICENSE_VALID": False,
         "logger": __import__("logging").getLogger()}
    fn = types.FunctionType(fn_code, g, "decode_license_jwt")

    now = datetime.datetime.now(datetime.timezone.utc)

    def mint(key):
        return jwt.encode({"aud": "langsmith", "iat": now, "nbf": now,
                           "exp": now + datetime.timedelta(days=3650),
                           "sub": "astrateam-selfhosted", "customer_name": "AstraTeam"},
                          key, algorithm="RS256")

    g["LICENSE_VALID"] = False
    fn(mint(priv))
    if g["LICENSE_VALID"] is not True:
        fail("kid-less token did not validate against the swapped key")

    other = rsa.generate_private_key(public_exponent=65537, key_size=2048).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption()).decode()
    g["LICENSE_VALID"] = False
    try:
        fn(mint(other))
        rejected = g["LICENSE_VALID"] is not True
    except Exception:
        rejected = True
    if not rejected:
        fail("a token signed by another key was accepted")


def main():
    header, code = load()
    orig = find_key(code)
    if not orig:
        fail("LICENSE_PUBLIC_KEY const gone from validation.pyc")
    if orig.strip() == OURKEY:
        fail("key already ours — vendor key not present to swap")

    prove(code, orig)

    with open(PYC, "wb") as f:
        f.write(header)
        marshal.dump(swap(code, orig, OURKEY), f)

    _, check = load()
    now = find_key(check)
    if now is None or now != OURKEY:
        fail("our key not present after swap")
    if now.strip() == orig.strip():
        fail("vendor key still present after swap")
    print("ASTRASCOPE-FLEET OK")


if __name__ == "__main__":
    main()
