#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

xcodegen generate

SIMULATOR_ID="$(
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json
import sys

devices = json.load(sys.stdin).get("devices", {})
available = []
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable"):
            available.append(device)

ipads = [device for device in available if device.get("name", "").startswith("iPad")]
selected = ipads[0] if ipads else (available[0] if available else None)
if selected is None:
    sys.exit(1)
print(selected["udid"])
'
)"

echo "Using simulator: $SIMULATOR_ID"
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true

xcodebuild test \
  -project FreeNote.xcodeproj \
  -scheme FreeNote \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO