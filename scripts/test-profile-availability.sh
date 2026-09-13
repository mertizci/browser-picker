#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD="$TASK_ROOT/build/profile-availability"
TASK_TEMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TEMP"' EXIT

# The Debug dylib lets these checks exercise the built application directly,
# without launching its app delegate or linking a second app entry point.
xcodebuild -quiet \
    -project "$TASK_ROOT/BrowserPicker.xcodeproj" \
    -scheme BrowserPicker -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$TASK_BUILD" \
    CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=YES build

TASK_PRODUCTS="$TASK_BUILD/Build/Products/Debug"
TASK_BINARY_DIR="$TASK_PRODUCTS/BrowserPicker.app/Contents/MacOS"
xcrun swiftc -parse-as-library \
    -I "$TASK_PRODUCTS" \
    "$TASK_ROOT/Tests/ProfileAvailabilityChecks.swift" \
    "$TASK_BINARY_DIR/BrowserPicker.debug.dylib" \
    -Xlinker -rpath -Xlinker "$TASK_BINARY_DIR" \
    -o "$TASK_TEMP/profile-availability-checks"

"$TASK_TEMP/profile-availability-checks"
