#!/usr/bin/env python3
"""Validate team, bundle, profile type, expiry, and matching private key before archive."""
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys

signing_dir = Path(sys.argv[1])
profile = plistlib.loads((signing_dir / "profile.plist").read_bytes())
team = os.environ["APPLE_TEAM_ID"]
method = os.environ["EXPORT_METHOD"]
bundle = "com.m1u13.weeknote"
if team not in profile.get("TeamIdentifier", []):
    raise SystemExit("Provisioning profile does not match APPLE_TEAM_ID")
if profile.get("Entitlements", {}).get("application-identifier") != f"{team}.{bundle}":
    raise SystemExit("Provisioning profile must have the explicit app identifier " + bundle)
if profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
    raise SystemExit("Provisioning profile has expired")
uuid = profile["UUID"]
if not re.fullmatch(r"[A-Fa-f0-9-]+", uuid):
    raise SystemExit("Invalid provisioning profile UUID")
debuggable = profile.get("Entitlements", {}).get("get-task-allow", False)
registered_devices = bool(profile.get("ProvisionedDevices"))
if method == "debugging" and not (debuggable and registered_devices):
    raise SystemExit("Debugging requires an iOS development profile with registered devices")
if method == "release-testing" and not (registered_devices and not debuggable):
    raise SystemExit("Release testing requires an Ad Hoc distribution profile")
if method == "app-store-connect" and (debuggable or registered_devices or profile.get("ProvisionsAllDevices")):
    raise SystemExit("App Store Connect requires an App Store distribution profile")
valid_identities = re.findall(r"\b[A-Fa-f0-9]{40}\b", (signing_dir / "identities.txt").read_text())
profile_certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
identity = next((value.upper() for value in valid_identities if value.upper() in profile_certificates), None)
if identity is None:
    raise SystemExit("The imported certificate/private key is missing or does not match the profile")
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
    output.write(f"IOS_PROFILE_UUID={uuid}\nIOS_SIGNING_IDENTITY={identity}\n")
export_options = {
    "method": method,
    "destination": "export",
    "teamID": team,
    "signingStyle": "manual",
    "signingCertificate": identity,
    "provisioningProfiles": {bundle: uuid},
    "manageAppVersionAndBuildNumber": False,
    "stripSwiftSymbols": True,
}
(signing_dir / "ExportOptions.plist").write_bytes(plistlib.dumps(export_options))
print("Signing certificate, app identifier, team, and provisioning profile are valid for " + method)

