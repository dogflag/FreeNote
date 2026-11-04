#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required" >&2
  exit 1
fi

xcodegen generate

rm -rf build
mkdir -p build/Payload

xcodebuild \
  -project FreeNote.xcodeproj \
  -scheme FreeNote \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="build/DerivedData/Build/Products/Release-iphoneos/FreeNote.app"
if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found at $APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" build/Payload/
(
  cd build
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent Payload FreeNote-unsigned.ipa
)

echo "Built: $ROOT_DIR/build/FreeNote-unsigned.ipa"