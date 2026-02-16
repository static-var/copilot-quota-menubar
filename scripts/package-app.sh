#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="${APP_NAME:-Copilot Quota}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-CopilotQuotaMenuBar}"
BUNDLE_ID="${BUNDLE_ID:-dev.staticvar.copilot-quota-menubar}"
AUTHOR="${AUTHOR:-staticvar}"

# Prefer a tag version like v1.2.3 when building in CI.
if [[ -z "${VERSION:-}" ]] && command -v git >/dev/null 2>&1; then
  if VERSION_TAG="$(git describe --tags --exact-match 2>/dev/null)"; then
    VERSION="${VERSION_TAG#v}"
  fi
fi
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$VERSION}"

DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$ROOT_DIR/.build/release/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

cat >"$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>$AUTHOR</string>
</dict>
</plist>
EOF

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  # Developer ID signing (recommended for distribution + notarization).
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
  # SwiftPM binaries are typically ad-hoc signed by the linker; re-sign the *bundle* so Gatekeeper
  # doesn't see a "signed app bundle" missing CodeResources (which shows up as "app is damaged").
  codesign --force --deep --sign - "$APP_DIR"
fi

ZIP_BASENAME="${ZIP_BASENAME:-${APP_NAME// /-}-${VERSION}-macOS-$(uname -m)}"
ZIP_PATH="$DIST_DIR/$ZIP_BASENAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Wrote: $ZIP_PATH"
