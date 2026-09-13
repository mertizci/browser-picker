#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: scripts/test-release-identity.sh <signed-release.app> [other-release.app ...]" >&2
  exit 2
fi

TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_TEMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TEMP"' EXIT

xcrun swiftc -parse-as-library \
  "$TASK_ROOT/BrowserPicker/Update/ReleaseIdentity.swift" \
  "$TASK_ROOT/scripts/verify-release-identity.swift" \
  -o "$TASK_TEMP/verify-release-identity"

for TASK_APP in "$@"; do
  "$TASK_TEMP/verify-release-identity" "$TASK_APP"
done

expect_rejected() {
  if "$TASK_TEMP/verify-release-identity" "$1"; then
    echo "FAIL: accepted $1" >&2
    exit 1
  fi
  echo "PASS: rejected $(basename "$1")"
}

# Modify disposable copies only; never launch an app or touch TCC settings.
ditto "$1" "$TASK_TEMP/AdHoc.app"
codesign --force --sign - "$TASK_TEMP/AdHoc.app"
expect_rejected "$TASK_TEMP/AdHoc.app"

ditto "$1" "$TASK_TEMP/Tampered.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' "$TASK_TEMP/Tampered.app/Contents/Info.plist"
expect_rejected "$TASK_TEMP/Tampered.app"

ditto "$1" "$TASK_TEMP/DebugIdentity.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.browserpicker.debug' "$TASK_TEMP/DebugIdentity.app/Contents/Info.plist"
codesign --force --sign - "$TASK_TEMP/DebugIdentity.app"
expect_rejected "$TASK_TEMP/DebugIdentity.app"

# With a local Developer ID identity, prove that a valid release signature
# with a changed DR is also rejected, rather than only rejecting bad signatures.
if [[ -n "${RELEASE_TEST_SIGN_IDENTITY:-}" ]]; then
  ditto "$1" "$TASK_TEMP/ChangedRequirement.app"
  codesign --force --sign "$RELEASE_TEST_SIGN_IDENTITY" --timestamp=none \
    --requirements '=designated => identifier "com.browserpicker.app"' \
    "$TASK_TEMP/ChangedRequirement.app"
  codesign --verify --strict "$TASK_TEMP/ChangedRequirement.app"
  expect_rejected "$TASK_TEMP/ChangedRequirement.app"
fi
