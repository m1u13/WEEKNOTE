#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
device_name="${SIMULATOR_NAME:-iPhone 16}"
runtime_suffix="${SIMULATOR_RUNTIME:-iOS-26-2}"
device_slug="$(printf '%s' "$device_name" | tr -cd '[:alnum:]')"
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
simulator_id="$(python3 -c '
import json, sys
with open("build/simulators.json") as handle:
    runtimes = json.load(handle)["devices"]
for runtime, devices in runtimes.items():
    if runtime.endswith(sys.argv[2]):
        for device in devices:
            if device["name"] == sys.argv[1] and device.get("isAvailable", True):
                print(device["udid"])
                sys.exit(0)
sys.exit("Requested simulator is unavailable: " + sys.argv[1] + " / " + sys.argv[2])
' "$device_name" "$runtime_suffix")"
echo "Testing on $device_name ($runtime_suffix): $simulator_id"
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl status_bar "$simulator_id" override --time "9:41" --batteryState charged --batteryLevel 100
result_path="build/TestResults-$device_slug.xcresult"
set +e
xcodebuild test \
  -project WEEKNOTE.xcodeproj \
  -scheme WEEKNOTE \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "build/test-$device_slug.log"
test_status=$?
set -e
mkdir -p "build/screenshots/$device_slug"
if [[ -d "$result_path" ]]; then
  xcrun xcresulttool get test-results summary \
    --path "$result_path" \
    --compact > "build/test-summary-$device_slug.json" || echo "No test summary could be exported. See the xcresult bundle."
  xcrun xcresulttool export attachments \
    --path "$result_path" \
    --output-path "build/screenshots/$device_slug/test-attachments" || echo "No test attachments could be exported. See the xcresult bundle."
fi
if [[ "$test_status" -ne 0 ]]; then
  exit "$test_status"
fi
app_path="build/DerivedData/Build/Products/Debug-iphonesimulator/WEEKNOTE.app"
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl ui "$simulator_id" appearance light
xcrun simctl launch --terminate-running-process "$simulator_id" com.m1u13.weeknote --uitesting
sleep 2
xcrun simctl io "$simulator_id" screenshot "build/screenshots/$device_slug/week-light.png"
xcrun simctl ui "$simulator_id" appearance dark
sleep 2
xcrun simctl io "$simulator_id" screenshot "build/screenshots/$device_slug/week-dark.png"
/usr/bin/ditto -c -k --keepParent "$app_path" "build/WEEKNOTE-simulator-$device_slug.zip"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf '### %s\n\nSimulator tests passed. Screenshots, test attachments, and the simulator app are included in the artifacts.\n' "$device_name" >> "$GITHUB_STEP_SUMMARY"
fi
