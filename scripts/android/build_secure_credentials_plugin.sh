#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATHLAND_PROJECT_ROOT="$(cd "$MATHLAND_SCRIPT_DIR/../.." && pwd)"
MATHLAND_GRADLE_ROOT="$MATHLAND_PROJECT_ROOT/android/plugins/secure_credentials"
MATHLAND_MODULE_ROOT="$MATHLAND_GRADLE_ROOT/secure_credentials"
MATHLAND_ADDON_BIN="$MATHLAND_PROJECT_ROOT/addons/mathland_secure_credentials/bin"

"$MATHLAND_GRADLE_ROOT/gradlew" \
  --project-dir "$MATHLAND_GRADLE_ROOT" \
  --no-daemon \
  --max-workers=4 \
  :secure_credentials:assembleDebug \
  :secure_credentials:assembleRelease

mkdir -p "$MATHLAND_ADDON_BIN/debug" "$MATHLAND_ADDON_BIN/release"
cp \
  "$MATHLAND_MODULE_ROOT/build/outputs/aar/secure_credentials-debug.aar" \
  "$MATHLAND_ADDON_BIN/debug/secure_credentials-debug.aar"
cp \
  "$MATHLAND_MODULE_ROOT/build/outputs/aar/secure_credentials-release.aar" \
  "$MATHLAND_ADDON_BIN/release/secure_credentials-release.aar"

test -s "$MATHLAND_ADDON_BIN/debug/secure_credentials-debug.aar"
test -s "$MATHLAND_ADDON_BIN/release/secure_credentials-release.aar"
