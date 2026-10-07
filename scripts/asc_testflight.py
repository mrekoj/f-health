#!/usr/bin/env python3
"""TestFlight helpers for BBHealth (ASC API).

    python3 scripts/asc_testflight.py app-id                 # print app id or exit 3 if no app record
    python3 scripts/asc_testflight.py group                  # ensure internal group + testers (BBH_TESTERS)
    python3 scripts/asc_testflight.py finalize <build> [mins] # wait for build, set encryption=false,
                                                             # add to group, print status
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asc import req, BUNDLE_IDENTIFIER

GROUP_NAME = os.environ.get("BBH_TESTFLIGHT_GROUP", "Nội bộ")
# Internal testers = users already in YOUR App Store Connect team. Comma-separated emails, e.g.
#   export BBH_TESTERS="ban@example.com,dongnghiep@example.com"
OWNER_EMAILS = [e.strip() for e in os.environ.get("BBH_TESTERS", "").split(",") if e.strip()]
OWNER_NAME = {}   # optional {email: (first, last)}


def app_id():
    r = req("GET", f"/v1/apps?filter[bundleId]={BUNDLE_IDENTIFIER}")
    d = [a for a in r.get("data", []) if a["attributes"]["bundleId"] == BUNDLE_IDENTIFIER]
    return d[0]["id"] if d else None


def ensure_group(aid):
    r = req("GET", f"/v1/apps/{aid}/betaGroups?limit=50")
    g = [x for x in r.get("data", []) if x["attributes"]["name"] == GROUP_NAME]
    if g:
        gid = g[0]["id"]
    else:
        r = req("POST", "/v1/betaGroups", {"data": {"type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
        if "data" not in r:
            print("WARN: cannot create beta group:", json.dumps(r)[:800], file=sys.stderr)
            return None, []
        gid = r["data"]["id"]
    notes = []
    for email in OWNER_EMAILS:
        r = req("GET", f"/v1/betaGroups/{gid}/betaTesters?limit=200")
        if any(t["attributes"].get("email", "").lower() == email for t in r.get("data", [])):
            notes.append(f"{email}: already in group")
            continue
        first, last = OWNER_NAME.get(email, ("", ""))
        r = req("POST", "/v1/betaTesters", {"data": {"type": "betaTesters",
            "attributes": {"email": email, "firstName": first, "lastName": last},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
        if "data" in r:
            notes.append(f"{email}: added")
            continue
        # Tester may already exist on the app -> link existing one to the group.
        r2 = req("GET", f"/v1/betaTesters?filter[email]={email}&filter[apps]={aid}")
        if r2.get("data"):
            tid = r2["data"][0]["id"]
            r3 = req("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters",
                     {"data": [{"type": "betaTesters", "id": tid}]})
            notes.append(f"{email}: linked existing tester ({'ok' if 'HTTPError' not in r3 else r3})")
        else:
            notes.append(f"{email}: FAILED {json.dumps(r)[:600]}")
    return gid, notes


def find_build(aid, number):
    r = req("GET", f"/v1/builds?filter[app]={aid}&filter[version]={number}&limit=5"
                   "&fields[builds]=version,processingState,usesNonExemptEncryption,uploadedDate")
    return (r.get("data") or [None])[0]


def finalize(number, minutes=15):
    aid = app_id()
    if not aid:
        print("No app record for", BUNDLE_IDENTIFIER, file=sys.stderr)
        return 3
    deadline = time.time() + minutes * 60
    b = None
    while time.time() < deadline:
        b = find_build(aid, number)
        state = b["attributes"]["processingState"] if b else "NOT_VISIBLE_YET"
        print(f"[{time.strftime('%H:%M:%S')}] build {number}: {state}", flush=True)
        if b and state in ("VALID", "FAILED", "INVALID"):
            break
        time.sleep(30)
    if not b:
        print(f"Build {number} chưa xuất hiện sau {minutes} phút — chạy lại: "
              f"python3 scripts/asc_testflight.py finalize {number}", file=sys.stderr)
        return 4
    bid = b["id"]
    if b["attributes"].get("usesNonExemptEncryption") is None:
        r = req("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                "attributes": {"usesNonExemptEncryption": False}}})
        print("export compliance:", "set false" if "data" in r else json.dumps(r)[:600])
    else:
        print("export compliance: already", b["attributes"]["usesNonExemptEncryption"])
    gid, notes = ensure_group(aid)
    for n in notes:
        print("tester:", n)
    if gid:
        r = req("POST", f"/v1/betaGroups/{gid}/relationships/builds",
                {"data": [{"type": "builds", "id": bid}]})
        print("group build link:", "ok" if "HTTPError" not in r else json.dumps(r)[:400])
    print(json.dumps({"appId": aid, "buildId": bid, "buildNumber": number,
                      "state": b["attributes"]["processingState"], "betaGroupId": gid}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "app-id":
        a = app_id()
        print(a or "")
        sys.exit(0 if a else 3)
    if cmd == "group":
        a = app_id()
        if not a:
            print("No app record", file=sys.stderr); sys.exit(3)
        gid, notes = ensure_group(a)
        print(json.dumps({"betaGroupId": gid, "notes": notes}, ensure_ascii=False, indent=1))
        sys.exit(0 if gid else 1)
    if cmd == "finalize" and len(sys.argv) > 2:
        sys.exit(finalize(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 15))
    print(__doc__); sys.exit(2)
