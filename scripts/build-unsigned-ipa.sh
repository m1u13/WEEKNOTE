#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild archive \
  -project WEEKNOTE.xcodeproj \
  -scheme WEEKNOTE \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/WEEKNOTE-unsigned.xcarchive \
  -derivedDataPath build/DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  2>&1 | tee build/archive-unsigned.log
app_path="$PWD/build/WEEKNOTE-unsigned.xcarchive/Products/Applications/WEEKNOTE.app"
test -x "$app_path/WEEKNOTE"
test -f "$app_path/Info.plist"
test -f "$app_path/PrivacyInfo.xcprivacy"
test -f "$app_path/Anton-Regular.ttf"
package_dir="$(mktemp -d "${TMPDIR:-/tmp}/weeknote-ipa.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Payload"
/usr/bin/ditto "$app_path" "$package_dir/Payload/WEEKNOTE.app"
/usr/bin/ditto -c -k --keepParent "$package_dir/Payload" "$PWD/build/WEEKNOTE-unsigned.ipa"
python3 scripts/verify-ipa.py build/WEEKNOTE-unsigned.ipa --unsigned
shasum -a 256 build/WEEKNOTE-unsigned.ipa > build/WEEKNOTE-unsigned.ipa.sha256
cat > build/UNSIGNED-IPA.txt <<'TEXT'
WEEKNOTE-unsigned.ipa is an unsigned iOS device build, packaged as Payload/WEEKNOTE.app.
It cannot be installed directly on a normal iPhone and is not a TestFlight/App Store build.
Use Xcode with your Apple development team, or run the signed-ipa workflow with a valid
Apple signing certificate and matching provisioning profile. See docs/BUILD.md.
The simulator app in the simulator artifact can be installed into an iOS Simulator on a Mac.
TEXT
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Unsigned IPA\n\n`WEEKNOTE-unsigned.ipa` was built for iOS devices. It requires Apple signing before installation on an iPhone. See `docs/BUILD.md`.\n' >> "$GITHUB_STEP_SUMMARY"
fi
