#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN_PATH="$RUNNER_TEMP/internet-speed-signing.keychain-db"
CERT_PATH="$RUNNER_TEMP/internet-speed-signing.p12"
APP_PATH="$ROOT_DIR/dist/InternetSpeed.app"
ZIP_PATH="$ROOT_DIR/dist/InternetSpeed.zip"

print -n "$APPLE_CERTIFICATE_P12" | base64 --decode > "$CERT_PATH"

security create-keychain -p "$APPLE_CERTIFICATE_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$APPLE_CERTIFICATE_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"

codesign --force --deep --options runtime --sign "$APPLE_SIGNING_IDENTITY" "$APP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

xcrun stapler staple "$APP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
