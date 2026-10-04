#!/usr/bin/env python3
"""Check the actual IPA payload, resource inclusion, and signing presence."""
import argparse
import plistlib
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("ipa", type=Path)
parser.add_argument("--unsigned", action="store_true")
args = parser.parse_args()
with zipfile.ZipFile(args.ipa) as archive:
    prefix = "Payload/WEEKNOTE.app/"
    names = set(archive.namelist())
    for resource in ("WEEKNOTE", "Info.plist", "PrivacyInfo.xcprivacy", "Anton-Regular.ttf", "Assets.car"):
        if prefix + resource not in names:
            raise SystemExit("IPA resource missing: " + resource)
    info = plistlib.loads(archive.read(prefix + "Info.plist"))
    if info.get("CFBundleIdentifier") != "com.m1u13.weeknote":
        raise SystemExit("Unexpected bundle identifier")
    if float(info.get("MinimumOSVersion", "0")) < 17:
        raise SystemExit("Unexpected deployment target")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise SystemExit("IPA contains a simulator build rather than a device build")
    if info.get("UIAppFonts") != ["Anton-Regular.ttf"]:
        raise SystemExit("Condensed font is not registered in the app")
    if not args.unsigned:
        for resource in ("embedded.mobileprovision", "_CodeSignature/CodeResources"):
            if prefix + resource not in names:
                raise SystemExit("Signed IPA resource missing: " + resource)
    print(f"Verified {args.ipa}: {info['CFBundleIdentifier']} / iOS {info['MinimumOSVersion']}")
