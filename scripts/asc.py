#!/usr/bin/env python3
"""Minimal App Store Connect API client for BBHealth (ES256 JWT).

    python3 scripts/asc.py get    '/v1/apps?filter[bundleId]=com.yourname.bbhealth'
    python3 scripts/asc.py post   /v1/profiles '{"data": {...}}'
    python3 scripts/asc.py patch  /v1/builds/<id> '{"data": {...}}'
    python3 scripts/asc.py delete /v1/profiles/<id>

Signing: uses `cryptography` if importable, else falls back to `openssl` CLI.
Importable: `from asc import req`. Config (your own App Store Connect account):
  ASC_KEY_ID, ASC_ISSUER_ID   required (App Store Connect > Users and Access > Integrations)
  ASC_KEY_PATH                optional, default ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
  ASC_DIST_CERT_ID            optional, default: newest Apple Distribution cert of the team
  ASC_PROFILE_NAME            optional, default "BBHealth-AppStore"
Bundle id + team come from Config/Local.xcconfig (PRODUCT_BUNDLE_IDENTIFIER, DEVELOPMENT_TEAM),
overridable by BBH_BUNDLE_ID / BBH_TEAM_ID. See docs/RELEASE.md. The key file is read from disk
at runtime; never put its content in the repo.
"""
import base64, json, os, subprocess, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _xcconfig(name):
    """Read NAME = value from Config/Local.xcconfig (then Config/Base.xcconfig)."""
    for fn in ("Local.xcconfig", "Base.xcconfig"):
        p = os.path.join(ROOT, "Config", fn)
        if not os.path.isfile(p):
            continue
        for line in open(p, encoding="utf-8"):
            line = line.split("//")[0].strip()
            k, _, v = line.partition("=")
            if k.strip() == name and v.strip():
                return v.strip()
    return ""


KEY_ID = os.environ.get("ASC_KEY_ID", "")
ISSUER = os.environ.get("ASC_ISSUER_ID", "")
_CANDIDATES = [
    os.environ.get("ASC_KEY_PATH", ""),
    os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
]
KEY_PATH = next((p for p in _CANDIDATES if p and os.path.isfile(p)), _CANDIDATES[1])

BUNDLE_IDENTIFIER = os.environ.get("BBH_BUNDLE_ID") or _xcconfig("PRODUCT_BUNDLE_IDENTIFIER")
TEAM_ID = os.environ.get("BBH_TEAM_ID") or _xcconfig("DEVELOPMENT_TEAM")
DIST_CERT_ID = os.environ.get("ASC_DIST_CERT_ID", "")   # empty -> asc_signing.py picks newest
PROFILE_NAME = os.environ.get("ASC_PROFILE_NAME", "BBHealth-AppStore")
BASE = "https://api.appstoreconnect.apple.com"


def _b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def _der_to_raw(der):
    """ECDSA DER (SEQUENCE{INTEGER r, INTEGER s}) -> 64-byte r||s."""
    def read_int(buf, i):
        assert buf[i] == 0x02
        ln = buf[i + 1]
        v = int.from_bytes(buf[i + 2:i + 2 + ln], "big")
        return v, i + 2 + ln
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def _sign(msg):
    try:
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives import hashes
        key = load_pem_private_key(open(KEY_PATH, "rb").read(), password=None)
        return _der_to_raw(key.sign(msg, ec.ECDSA(hashes.SHA256())))
    except ImportError:
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                             input=msg, capture_output=True, check=True).stdout
        return _der_to_raw(der)


def token():
    if not (KEY_ID and ISSUER and os.path.isfile(KEY_PATH)):
        sys.exit("Missing App Store Connect key: set ASC_KEY_ID, ASC_ISSUER_ID and put AuthKey_<KEY_ID>.p8 "
                 "in ~/.appstoreconnect/private_keys/ (or set ASC_KEY_PATH). See docs/RELEASE.md.")
    now = int(time.time())
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"}
    seg = _b64u(json.dumps(header).encode()) + b"." + _b64u(json.dumps(payload).encode())
    return (seg + b"." + _b64u(_sign(seg))).decode()


def req(method, path, body=None, tries=4):
    """One API call; retries network errors / 5xx. Returns parsed JSON, or
    {"HTTPError": code, "body": ...} on 4xx."""
    if not path.startswith("http"):
        path = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(tries):
        r = urllib.request.Request(path, data=data, method=method.upper(), headers={
            "Authorization": "Bearer " + token(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(r, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {"status": resp.status}
        except urllib.error.HTTPError as e:
            err = {"HTTPError": e.code, "body": e.read().decode(errors="replace")}
            if e.code < 500 or attempt == tries - 1:
                return err
        except Exception as e:  # noqa: BLE001
            if attempt == tries - 1:
                return {"error": repr(e)}
        time.sleep(2 * (attempt + 1))


def get(path):
    return req("GET", path)


def main(argv):
    if len(argv) < 3 or argv[1].lower() not in ("get", "post", "patch", "delete"):
        print(__doc__, file=sys.stderr)
        return 2
    method, path = argv[1].upper(), argv[2]
    body = json.loads(argv[3]) if len(argv) > 3 else None
    res = req(method, path, body)
    print(json.dumps(res, ensure_ascii=False, indent=1))
    return 1 if isinstance(res, dict) and ("HTTPError" in res or "error" in res) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
