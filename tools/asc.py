#!/usr/bin/env python3
"""A small App Store Connect API client — the stock python3 of a Mac, no third-party modules.

    tools/asc.py builds                  recent uploads: version, build, platform, processing state
    tools/asc.py bundle-id [--create]    look up (or register) the app's bundle ID

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
            return r.status, json.load(r)
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


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "builds"
    if cmd == "builds":
        builds()
    elif cmd == "bundle-id":
        bundle_id("--create" in sys.argv)
    else:
        sys.exit(__doc__)
