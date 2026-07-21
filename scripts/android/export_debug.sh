#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATHLAND_PROJECT_ROOT="$(cd "$MATHLAND_SCRIPT_DIR/../.." && pwd)"
MATHLAND_GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
MATHLAND_DEBUG_APK="$MATHLAND_PROJECT_ROOT/dist/MathLand-debug-arm64.apk"
MATHLAND_GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.vfs.watch=false -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=4"

mkdir -p "$MATHLAND_PROJECT_ROOT/dist"
env npm --prefix "$MATHLAND_PROJECT_ROOT" run verify:toolchain
"$MATHLAND_PROJECT_ROOT/scripts/android/build_secure_credentials_plugin.sh"
GRADLE_OPTS="$MATHLAND_GRADLE_OPTS" "$MATHLAND_GODOT_BIN" \
  --headless \
  --path "$MATHLAND_PROJECT_ROOT" \
  --install-android-build-template \
  --export-debug "Android Debug" \
  "$MATHLAND_DEBUG_APK"
"$MATHLAND_PROJECT_ROOT/scripts/android/inspect_manifest.sh" "$MATHLAND_DEBUG_APK"
