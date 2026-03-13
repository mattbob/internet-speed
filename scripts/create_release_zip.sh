#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="$ROOT_DIR/dist/InternetSpeed.xcarchive"
APP_PATH="$ROOT_DIR/dist/InternetSpeed.app"
ZIP_PATH="$ROOT_DIR/dist/InternetSpeed.zip"

rm -rf "$ROOT_DIR/dist"
mkdir -p "$ROOT_DIR/dist"

if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  xcodebuild \
    -project "$ROOT_DIR/InternetSpeed.xcodeproj" \
    -scheme InternetSpeed \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    archive

  cp -R "$ARCHIVE_PATH/Products/Applications/InternetSpeed.app" "$APP_PATH"
else
  xcodebuild \
    -project "$ROOT_DIR/InternetSpeed.xcodeproj" \
    -target InternetSpeed \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO \
    build

  cp -R "$ROOT_DIR/build/Release/InternetSpeed.app" "$APP_PATH"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
