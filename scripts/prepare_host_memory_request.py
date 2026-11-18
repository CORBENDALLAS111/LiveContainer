"""Prepare a *host* Increased Memory Limit request for the final integrated LC+ IPA.

SideStore must use its Apple Developer Portal session and real provisioning
profile to grant the entitlement when the user installs/re-signs LC+.
This file does NOT grant any entitlement, sign the app or allocate memory.
"""
import argparse
import json
import pathlib
import plistlib
import re

ENTITLEMENT = "com.apple.developer.kernel.increased-memory-limit"
MARKER = "LCOSIncreasedMemoryRequest.plist"


def prepare_host(app: pathlib.Path, entitlements: pathlib.Path) -> dict:
    app = pathlib.Path(app)
    with (app / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    with pathlib.Path(entitlements).open("rb") as source:
        declared = plistlib.load(source)

    identifier = info.get("CFBundleIdentifier")
    executable = info.get("CFBundleExecutable")
    if not isinstance(identifier, str) or re.fullmatch(
        r"[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)+", identifier
    ) is None:
        raise ValueError("Invalid LC+ bundle identifier; no memory request produced")
    if executable != "LiveContainer" or not (app / executable).is_file():
        raise ValueError("Expected the real LC+ host executable")
    if declared.get(ENTITLEMENT) is not True:
        raise ValueError("LC+ host entitlement was not declared by the Xcode project")

    payload = {"schema": 1, "requested": True, "bundleIdentifier": identifier}
    marker = app / MARKER
    marker.write_bytes(plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True))
    if plistlib.loads(marker.read_bytes()) != payload:
        raise ValueError("Host memory request marker verification failed")
    return {
        "bundle": identifier,
        "requested_entitlement": ENTITLEMENT,
        "marker": MARKER,
        "apple_profile_granted": False,
        "installed_signature_verified": False,
    }


if __name__ == "__main__":
    cli = argparse.ArgumentParser()
    cli.add_argument("app", type=pathlib.Path)
    cli.add_argument("--entitlements", required=True, type=pathlib.Path)
    args = cli.parse_args()
    print(json.dumps(prepare_host(args.app, args.entitlements), indent=2))
