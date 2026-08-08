import base64
import json
import os
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

import litellm.proxy.auth.litellm_license as m

pem = os.path.join(os.path.dirname(m.__file__), "public_key.pem")
if not os.path.exists(pem):
    sys.exit(f"ASTRALLM FAIL: public_key.pem not found at {pem}")

priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
with open(pem, "wb") as f:
    f.write(
        priv.public_key().public_bytes(
            serialization.Encoding.PEM,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    )

msg = json.dumps(
    {
        "expiration_date": "2099-12-31",
        "user_id": "selftest",
        "allowed_features": ["all"],
        "max_users": 1,
        "max_teams": 1,
    }
).encode()
sig = priv.sign(
    msg,
    padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=padding.PSS.MAX_LENGTH),
    hashes.SHA256(),
)
os.environ["LITELLM_LICENSE"] = base64.b64encode(msg + b"." + sig).decode()

from litellm.proxy.auth.litellm_license import LicenseCheck

c = LicenseCheck()
if not (
    c.verify_license_without_api_request(c.public_key, c.license_str) is True
    and c.is_premium() is True
):
    sys.exit("ASTRALLM SELF-TEST FAILED")
