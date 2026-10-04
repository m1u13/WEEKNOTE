#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${IOS_SIGNING_DIR:-}" ]]; then
  case "$IOS_SIGNING_DIR" in
    "${RUNNER_TEMP:?}/weeknote-signing."*) ;;
    *) echo "Refusing to remove an unexpected signing directory" >&2; exit 1 ;;
  esac
  security delete-keychain "$IOS_SIGNING_DIR/signing.keychain-db" 2>/dev/null || true
  rm -rf "$IOS_SIGNING_DIR"
fi
if [[ -n "${IOS_PROFILE_UUID:-}" ]]; then
  for profile_dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    rm -f "$profile_dir/$IOS_PROFILE_UUID.mobileprovision"
  done
fi

