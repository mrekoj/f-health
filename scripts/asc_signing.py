#!/usr/bin/env python3
"""Idempotent signing setup for BBHealth via ASC API.

1. bundleId from Config/Local.xcconfig (create if missing, platform IOS, name BBHealth)
2. capability HEALTHKIT on that bundleId
3. (re)create IOS_APP_STORE profile ASC_PROFILE_NAME (default "BBHealth-AppStore") with your
   Apple Distribution cert (ASC_DIST_CERT_ID, or the newest one of the team),
   install <uuid>.mobileprovision into both Xcode profile folders.

Prints a JSON summary. Usage: python3 scripts/asc_signing.py [--keep-profile]
"""
import base64, json, os, plistlib, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import req, BUNDLE_IDENTIFIER, DIST_CERT_ID, PROFILE_NAME

PROFILE_DIRS = [
    os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
    os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
]


def die(msg, res=None):
    print("ERROR:", msg, json.dumps(res, ensure_ascii=False)[:2000] if res else "", file=sys.stderr)
    sys.exit(1)


def ensure_bundle_id():
    r = req("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_IDENTIFIER}")
    hits = [d for d in r.get("data", []) if d["attributes"]["identifier"] == BUNDLE_IDENTIFIER]
    if hits:
        return hits[0]["id"], False
    r = req("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": BUNDLE_IDENTIFIER, "name": "BBHealth", "platform": "IOS"}}})
    if "data" not in r:
        die("create bundleId failed", r)
    return r["data"]["id"], True


def ensure_healthkit(bid):
    r = req("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities")
    types = [d["attributes"]["capabilityType"] for d in r.get("data", [])]
    if "HEALTHKIT" in types:
        return "already"
    r = req("POST", "/v1/bundleIdCapabilities", {"data": {
        "type": "bundleIdCapabilities", "attributes": {"capabilityType": "HEALTHKIT"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
    if "data" not in r:
        die("enable HEALTHKIT failed", r)
    return "enabled"


def install(content_b64):
    raw = base64.b64decode(content_b64)
    m = re.search(rb"<\?xml.*</plist>", raw, re.S)
    info = plistlib.loads(m.group(0))
    uuid = info["UUID"]
    paths = []
    for d in PROFILE_DIRS:
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, f"{uuid}.mobileprovision")
        with open(p, "wb") as f:
            f.write(raw)
        paths.append(p)
    return uuid, info.get("ExpirationDate"), paths


def dist_cert_id():
    if DIST_CERT_ID:
        return DIST_CERT_ID
    r = req("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=50")
    certs = sorted(r.get("data", []), key=lambda d: d["attributes"].get("expirationDate") or "", reverse=True)
    if not certs:
        die("no Apple Distribution certificate in this team — create one in Xcode → Settings → Accounts "
            "→ Manage Certificates → + Apple Distribution (see docs/RELEASE.md)", r)
    return certs[0]["id"]


def recreate_profile(bid, keep=False):
    r = req("GET", f"/v1/profiles?filter[name]={PROFILE_NAME}&limit=50")
    olds = [d for d in r.get("data", []) if d["attributes"]["name"] == PROFILE_NAME]
    if keep and olds and olds[0]["attributes"].get("profileState") == "ACTIVE":
        uuid, exp, paths = install(olds[0]["attributes"]["profileContent"])
        return olds[0]["id"], uuid, exp, paths, 0
    for o in olds:
        req("DELETE", f"/v1/profiles/{o['id']}")
    r = req("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": dist_cert_id()}]}}}})
    if "data" not in r:
        die("create profile failed", r)
    uuid, exp, paths = install(r["data"]["attributes"]["profileContent"])
    return r["data"]["id"], uuid, exp, paths, len(olds)


if __name__ == "__main__":
    if not BUNDLE_IDENTIFIER:
        die("PRODUCT_BUNDLE_IDENTIFIER missing — create Config/Local.xcconfig (see docs/SETUP.md)")
    bid, created = ensure_bundle_id()
    cap = ensure_healthkit(bid)
    pid, uuid, exp, paths, deleted = recreate_profile(bid, keep="--keep-profile" in sys.argv)
    print(json.dumps({"bundleIdResource": bid, "bundleIdCreated": created, "healthkit": cap,
                      "profileId": pid, "profileUUID": uuid, "profileExpires": str(exp),
                      "oldProfilesDeleted": deleted, "installed": paths}, indent=1))
