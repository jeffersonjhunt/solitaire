#!/usr/bin/env python3
"""A small App Store Connect API client — the stock python3 of a Mac, no third-party modules.

    tools/asc.py builds                  recent uploads: version, build, platform, processing state
    tools/asc.py bundle-id [--create]    look up (or register) the app's bundle ID
    tools/asc.py whats-new <build> <file>   the "What to Test" notes testers see for that build (all
                                         its platforms), from a text file
    tools/asc.py pricing [--set]         price and countries: free, every territory, and new ones
                                         as Apple adds them; --set creates whichever is missing
    tools/asc.py gamecenter [--create]   Game Center and iCloud for the app: the bundle ID's
                                         capabilities, the four leaderboards and their set (spec
                                         "Scores"); --create adds whatever is missing, and only that

Credentials come from the api.env that `make` reads (ASC_ENV, default
$HOME/.config/appstoreconnect/api.env): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH. The ES256 token is
signed with openssl, so the key never leaves the file.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "com.oneoffendeavors.solitaire"
ENV_FILE = os.environ.get("ASC_ENV") or os.path.join(os.environ["HOME"], ".config/appstoreconnect/api.env")


def load_env():
    try:
        with open(ENV_FILE) as f:
            return dict(line.strip().split("=", 1) for line in f if "=" in line and not line.startswith("#"))
    except OSError:
        sys.exit(f"no App Store Connect settings at {ENV_FILE} (see README › Signing)")


ENV = load_env()


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def der_to_raw(der):
    """openssl's ECDSA signature (DER SEQUENCE of r, s) -> the 64-byte r||s a JWT carries."""
    i = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert der[i] == 0x02, "unexpected signature encoding"
        n = der[i + 1]
        out += der[i + 2:i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out


def token():
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": ENV["ASC_KEY_ID"], "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": ENV["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
                           "aud": "appstoreconnect-v1"}).encode())
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", ENV["ASC_KEY_PATH"]],
                         input=head + b"." + body, capture_output=True, check=True).stdout
    return (head + b"." + body + b"." + b64(der_to_raw(sig))).decode()


def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, json.loads(body) if body else {}       # 204 No Content: no body
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def get(path):
    status, data = call("GET", path)
    if status != 200:
        sys.exit(f"App Store Connect said {status}: {json.dumps(data.get('errors', data))[:400]}")
    return data


def builds():
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID} — create the app record first")
    app = apps[0]
    print(f"{app['attributes']['name']} ({BUNDLE_ID})")
    data = get(f"/v1/builds?filter[app]={app['id']}&sort=-uploadedDate&limit=10&include=preReleaseVersion")
    versions = {v["id"]: v["attributes"] for v in data.get("included", []) if v["type"] == "preReleaseVersions"}
    if not data["data"]:
        print("  no builds yet (a fresh upload takes a few minutes to appear)")
    for b in data["data"]:
        a = b["attributes"]
        pre = versions.get(b["relationships"]["preReleaseVersion"]["data"]["id"], {})
        print(f"  {pre.get('platform', '?'):6} {pre.get('version', '?'):5} build {a['version']:>12}  "
              f"{a['processingState']:10}  uploaded {a['uploadedDate'][:16].replace('T', ' ')}"
              + ("  EXPIRED" if a.get("expired") else ""))


def bundle_id(create):
    data = get("/v1/bundleIds?filter[identifier]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    for d in data:
        print(f"{d['attributes']['identifier']}  {d['attributes']['platform']}  team {d['attributes']['seedId']}")
    if not data and create:
        status, d = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": BUNDLE_ID, "name": "Solitaire", "platform": "UNIVERSAL"}}})
        if status != 201:
            sys.exit(f"could not register {BUNDLE_ID}: {status} {json.dumps(d.get('errors', d))[:400]}")
        print(f"registered {BUNDLE_ID} (UNIVERSAL)")
    elif not data:
        print(f"{BUNDLE_ID} is not registered (pass --create)")


# Spec "Scores": one board per draw mode and difficulty, each player's best kept, highest first.
LEADERBOARDS = [
    ("com.oneoffendeavors.solitaire.draw1", "Draw 1"),
    ("com.oneoffendeavors.solitaire.draw3", "Draw 3"),
    ("com.oneoffendeavors.solitaire.draw1.hardcore", "Draw 1 · Hard Core"),
    ("com.oneoffendeavors.solitaire.draw3.hardcore", "Draw 3 · Hard Core"),
]
LEADERBOARD_SET = ("com.oneoffendeavors.solitaire.leaderboards", "Solitaire")
CAPABILITIES = {
    "GAME_CENTER": None,
    "ICLOUD": [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6"}]}],
}


def post(path, body, what):
    status, data = call("POST", path, body)
    if status not in (200, 201, 204):
        sys.exit(f"could not {what}: {status} {json.dumps(data.get('errors', data) if data else '')[:500]}")
    print(f"  created: {what}")
    return data


def rel(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def gamecenter(create):
    """Reports, and with create adds, what Game Center and iCloud need. Never changes or removes
    anything that exists."""
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID}")
    app = apps[0]["id"]
    bundle = get("/v1/bundleIds?filter[identifier]=" + urllib.parse.quote(BUNDLE_ID))["data"][0]["id"]

    have = {c["attributes"]["capabilityType"]
            for c in get(f"/v1/bundleIds/{bundle}/bundleIdCapabilities")["data"]}
    for cap, settings in CAPABILITIES.items():
        print(f"capability {cap}: {'on' if cap in have else 'missing'}")
        if cap not in have and create:
            attributes = {"capabilityType": cap}
            if settings:
                attributes["settings"] = settings
            post("/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": attributes,
                 "relationships": {"bundleId": rel("bundleIds", bundle)}}}, f"capability {cap}")

    status, detail = call("GET", f"/v1/apps/{app}/gameCenterDetail")
    detail_id = detail["data"]["id"] if status == 200 and detail.get("data") else None
    print(f"Game Center for the app: {'on' if detail_id else 'missing'}")
    if not detail_id:
        if not create:
            return
        detail_id = post("/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
                         "relationships": {"app": rel("apps", app)}}}, "Game Center detail")["data"]["id"]

    boards = {b["attributes"]["vendorIdentifier"]: b["id"]
              for b in get(f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=50")["data"]}
    for vendor, name in LEADERBOARDS:
        print(f"leaderboard {vendor}: {'present' if vendor in boards else 'missing'}")
        if vendor in boards or not create:
            continue
        board = post("/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards", "attributes": {
            "referenceName": f"Solitaire — {name}", "vendorIdentifier": vendor, "defaultFormatter": "INTEGER",
            "submissionType": "BEST_SCORE", "scoreSortType": "DESC", "scoreRangeStart": "0",
            "scoreRangeEnd": "1000"}, "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}},
            f"leaderboard {name}")["data"]["id"]
        boards[vendor] = board
        post("/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
             "attributes": {"locale": "en-US", "name": name, "formatterSuffix": " points",
                            "formatterSuffixSingular": " point"},
             "relationships": {"gameCenterLeaderboard": rel("gameCenterLeaderboards", board)}}},
             f"English name for {name}")

    sets = {s["attributes"]["vendorIdentifier"]: s["id"]
            for s in get(f"/v1/gameCenterDetails/{detail_id}/gameCenterLeaderboardSets?limit=50")["data"]}
    vendor, name = LEADERBOARD_SET
    print(f"leaderboard set {vendor}: {'present' if vendor in sets else 'missing'}")
    if vendor not in sets and create:
        sets[vendor] = post("/v1/gameCenterLeaderboardSets", {"data": {"type": "gameCenterLeaderboardSets",
            "attributes": {"referenceName": f"{name} leaderboards", "vendorIdentifier": vendor},
            "relationships": {"gameCenterDetail": rel("gameCenterDetails", detail_id)}}}, "leaderboard set")["data"]["id"]
        post("/v1/gameCenterLeaderboardSetLocalizations", {"data": {"type": "gameCenterLeaderboardSetLocalizations",
             "attributes": {"locale": "en-US", "name": name},
             "relationships": {"gameCenterLeaderboardSet": rel("gameCenterLeaderboardSets", sets[vendor])}}},
             "English name for the set")
    if vendor in sets:
        members = {m["id"] for m in get(f"/v1/gameCenterLeaderboardSets/{sets[vendor]}/relationships/gameCenterLeaderboards?limit=50")["data"]}
        missing = [boards[v] for v, _ in LEADERBOARDS if v in boards and boards[v] not in members]
        print(f"  set members: {len(members)} of {len(LEADERBOARDS)}")
        if missing and create:
            post(f"/v1/gameCenterLeaderboardSets/{sets[vendor]}/relationships/gameCenterLeaderboards",
                 {"data": [{"type": "gameCenterLeaderboards", "id": b} for b in missing]},
                 f"{len(missing)} leaderboards added to the set")


def app_id():
    apps = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"]
    if not apps:
        sys.exit(f"no App Store Connect app with bundle ID {BUNDLE_ID}")
    return apps[0]["id"]


def pricing(apply):
    """Free, in every territory (the 1.1 decision). Neither can be changed back to "unset", only
    to another price or list, so --set only ever creates what is missing."""
    app = app_id()
    status, prices = call("GET", f"/v1/appPriceSchedules/{app}/manualPrices?include=appPricePoint")
    points = [i["attributes"].get("customerPrice") for i in prices.get("included", [])] if status == 200 else []
    print(f"  price: {'free' if points == ['0.0'] else (points or 'not set')}")
    if not points and apply:
        free = [p for p in get(f"/v1/apps/{app}/appPricePoints?filter[territory]=USA&limit=5")["data"]
                if p["attributes"]["customerPrice"] in ("0", "0.0", "0.00")]
        if len(free) != 1:
            sys.exit("could not find the free price point")
        post("/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": rel("apps", app), "baseTerritory": rel("territories", "USA"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": rel("appPricePoints", free[0]["id"])}}]},
            "price schedule: free (base territory USA)")
    status, avail = call("GET", f"/v1/apps/{app}/appAvailabilityV2")
    if status == 200:
        a = avail["data"]["attributes"]
        print(f"  availability: set (new territories automatically: {a.get('availableInNewTerritories')})")
    else:
        print("  availability: not set")
        if apply:
            territories = [t["id"] for t in get("/v1/territories?limit=200")["data"]]
            post("/v2/appAvailabilities", {
                "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                         "relationships": {"app": rel("apps", app), "territoryAvailabilities": {
                             "data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
                "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                              "relationships": {"territory": rel("territories", t)}} for t in territories]},
                f"availability: all {len(territories)} territories, and new ones")


def whats_new(build_number, path):
    """Sets the English "What to Test" text on every platform's upload of a build."""
    text = open(path).read().strip()
    if not text or len(text) > 4000:
        sys.exit(f"the notes must be 1-4000 characters (they are {len(text)})")
    app = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID))["data"][0]["id"]
    builds = get(f"/v1/builds?filter[app]={app}&filter[version]={urllib.parse.quote(build_number)}&limit=10")["data"]
    if not builds:
        sys.exit(f"no build {build_number} yet (an upload takes a few minutes to appear)")
    for b in builds:
        locs = get(f"/v1/builds/{b['id']}/betaBuildLocalizations")["data"]
        mine = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
        if mine:
            status, data = call("PATCH", f"/v1/betaBuildLocalizations/{mine['id']}", {"data": {
                "type": "betaBuildLocalizations", "id": mine["id"], "attributes": {"whatsNew": text}}})
        else:
            status, data = call("POST", "/v1/betaBuildLocalizations", {"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
                "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
        if status not in (200, 201):
            sys.exit(f"could not set the notes on build {b['id']}: {status} {json.dumps(data.get('errors', data))[:400]}")
        print(f"  notes set on {build_number} ({b['id']})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "builds":
        builds()
    elif cmd == "bundle-id":
        bundle_id("--create" in sys.argv)
    elif cmd == "whats-new" and len(sys.argv) == 4:
        whats_new(sys.argv[2], sys.argv[3])
    elif cmd == "pricing":
        pricing("--set" in sys.argv)
    elif cmd == "gamecenter":
        gamecenter("--create" in sys.argv)
    else:
        sys.exit(__doc__)
