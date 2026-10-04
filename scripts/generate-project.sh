#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. On macOS: brew install xcodegen" >&2
  exit 1
fi
xcodegen --version
xcodegen generate --spec project.yml
plutil -lint WEEKNOTE/Info.plist WEEKNOTE/Resources/PrivacyInfo.xcprivacy

