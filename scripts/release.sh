#!/usr/bin/env bash
#
# Build, sign, notarize and package Browser Picker for distribution (Homebrew Cask).
#
# Prerequisites:
#   1. A "Developer ID Application" certificate in your Keychain:
#        security find-identity -v -p codesigning | grep "Developer ID Application"
#   2. A stored notarization profile (one-time setup):
#        xcrun notarytool store-credentials browser-picker-notary \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "app-specific-password"   # from appleid.apple.com
#
# Usage:
#   scripts/release.sh 1.0.0
#
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>  (e.g. 1.0.0)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-browser-picker-notary}"
SCHEME="BrowserPicker"
APP_NAME="BrowserPicker.app"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
EXPORT_DIR="$BUILD_DIR/export"
ARCHIVE="$BUILD_DIR/BrowserPicker.xcarchive"
ZIP_PATH="$ROOT/build/BrowserPicker-$VERSION.zip"

echo "==> Resolving Developer ID Application identity"
# Allow overriding via SIGN_IDENTITY (e.g. in CI); otherwise auto-detect.
DEV_ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')}"
if [[ -z "${DEV_ID:-}" ]]; then
  echo "ERROR: No 'Developer ID Application' certificate found in the Keychain." >&2
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application." >&2
  exit 1
fi
echo "    Using: $DEV_ID"

echo "==> Generating Xcode project"
(cd "$ROOT" && xcodegen generate)

echo "==> Archiving (Release)"
rm -rf "$BUILD_DIR"
xcodebuild -project "$ROOT/BrowserPicker.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEV_ID" \
  MARKETING_VERSION="$VERSION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  archive

echo "==> Exporting signed .app"
mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE/Products/Applications/$APP_NAME" "$EXPORT_DIR/"

APP_PATH="$EXPORT_DIR/$APP_NAME"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Creating ZIP for notarization"
mkdir -p "$ROOT/build"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to Apple notary service"
# Notarization credentials: prefer explicit env vars (CI), else a stored
# Keychain profile (local dev).
if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "    Using Apple ID credentials from environment"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
else
  echo "    Using Keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
fi

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "==> Re-zipping stapled app"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Final Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

# Expose outputs for CI consumers.
echo "$SHA" > "$ROOT/build/BrowserPicker-$VERSION.sha256"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$VERSION"
    echo "sha256=$SHA"
    echo "zip_path=$ZIP_PATH"
  } >> "$GITHUB_OUTPUT"
fi

echo ""
echo "============================================================"
echo " Release artifact ready"
echo "   File:    $ZIP_PATH"
echo "   Version: $VERSION"
echo "   sha256:  $SHA"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Create a GitHub release tagged v$VERSION and upload the ZIP."
echo "  2. Update Casks/browser-picker.rb with version $VERSION and the sha256 above."
echo "  3. Push your tap so users can: brew install --cask mertizci/tap/browser-picker"
