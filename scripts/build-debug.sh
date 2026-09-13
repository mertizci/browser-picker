#!/usr/bin/env bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_BUILD="${DEBUG_BUILD_DIR:-$TASK_ROOT/build/debug-preview}"
TASK_PRODUCTS="$TASK_BUILD/Products"
TASK_APP="$TASK_PRODUCTS/BrowserPicker Debug.app"
TASK_ZIP="$TASK_BUILD/BrowserPicker-Debug.zip"

cd "$TASK_ROOT"
xcodegen generate
xcodebuild -quiet -project BrowserPicker.xcodeproj -scheme BrowserPicker \
    -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$TASK_BUILD/DerivedData" \
    CONFIGURATION_BUILD_DIR="$TASK_PRODUCTS" \
    PRODUCT_NAME="BrowserPicker Debug" PRODUCT_MODULE_NAME=BrowserPicker \
    PRODUCT_BUNDLE_IDENTIFIER=com.browserpicker.debug \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG BROWSER_PICKER_DEBUG' \
    CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ONLY_ACTIVE_ARCH=YES build

# Prefer a stable local development identity for macOS permission testing.
TASK_IDENTITY="${DEBUG_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')}"
codesign --force --sign "${TASK_IDENTITY:--}" "$TASK_APP"
codesign --verify --strict "$TASK_APP"
ditto -c -k --sequesterRsrc --keepParent "$TASK_APP" "$TASK_ZIP"
printf 'App: %s\nZIP: %s\n' "$TASK_APP" "$TASK_ZIP"
