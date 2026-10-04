#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for variable in BUILD_CERTIFICATE_BASE64 P12_PASSWORD BUILD_PROVISION_PROFILE_BASE64 KEYCHAIN_PASSWORD APPLE_TEAM_ID EXPORT_METHOD RUNNER_TEMP GITHUB_ENV; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing signing configuration: $variable. See docs/BUILD.md." >&2
    exit 1
  fi
done
case "$EXPORT_METHOD" in
  release-testing|debugging|app-store-connect) ;;
  *) echo "Unsupported export method" >&2; exit 1 ;;
esac
signing_dir="$(mktemp -d "$RUNNER_TEMP/weeknote-signing.XXXXXX")"
printf 'IOS_SIGNING_DIR=%s\n' "$signing_dir" >> "$GITHUB_ENV"
keychain_path="$signing_dir/signing.keychain-db"
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$signing_dir/certificate.p12"
printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$signing_dir/profile.mobileprovision"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"
security import "$signing_dir/certificate.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
security find-identity -v -p codesigning "$keychain_path" > "$signing_dir/identities.txt"
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
python3 scripts/validate-signing.py "$signing_dir"
profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$signing_dir/profile.plist")"
for profile_dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$profile_dir"
  cp "$signing_dir/profile.mobileprovision" "$profile_dir/$profile_uuid.mobileprovision"
done

