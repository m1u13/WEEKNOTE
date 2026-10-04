#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for variable in APPLE_TEAM_ID IOS_PROFILE_UUID IOS_SIGNING_IDENTITY IOS_SIGNING_DIR; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Run install-signing.sh before exporting the signed IPA." >&2
    exit 1
  fi
done
mkdir -p build/export
xcodebuild -version
xcodebuild archive \
  -project WEEKNOTE.xcodeproj \
  -scheme WEEKNOTE \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/WEEKNOTE-signed.xcarchive \
  -derivedDataPath build/SignedDerivedData \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$IOS_PROFILE_UUID" \
  CODE_SIGN_IDENTITY="$IOS_SIGNING_IDENTITY" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  2>&1 | tee build/archive-signed.log
codesign --verify --deep --strict build/WEEKNOTE-signed.xcarchive/Products/Applications/WEEKNOTE.app
xcodebuild -exportArchive \
  -archivePath build/WEEKNOTE-signed.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist "$IOS_SIGNING_DIR/ExportOptions.plist" \
  2>&1 | tee build/export-signed.log
for ipa_path in build/export/*.ipa; do
  test -f "$ipa_path"
  python3 scripts/verify-ipa.py "$ipa_path"
  shasum -a 256 "$ipa_path" > "$ipa_path.sha256"
done
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### Signed IPA\n\nExported with `%s`. The artifact contains the signed IPA and checksum.\n' "$EXPORT_METHOD" >> "$GITHUB_STEP_SUMMARY"
fi

