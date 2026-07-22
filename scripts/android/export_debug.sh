#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATHLAND_PROJECT_ROOT="$(cd "$MATHLAND_SCRIPT_DIR/../.." && pwd)"
MATHLAND_GODOT_BIN="${GODOT_BIN:-/opt/homebrew/bin/godot}"
MATHLAND_DEBUG_APK="$MATHLAND_PROJECT_ROOT/dist/MathLand-debug-arm64.apk"
MATHLAND_GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.vfs.watch=false -Dorg.gradle.daemon=false -Dorg.gradle.workers.max=4"
MATHLAND_STAGE_PARENT="${TMPDIR:-/tmp}"
MATHLAND_STAGE_ROOT="$(mktemp -d "$MATHLAND_STAGE_PARENT/mathland-android-export.XXXXXX")"
MATHLAND_STAGED_APK="$MATHLAND_STAGE_ROOT/dist/MathLand-debug-arm64.apk"

cleanup_mathland_stage() {
  if [ -n "$MATHLAND_STAGE_ROOT" ] && [ -d "$MATHLAND_STAGE_ROOT" ]; then
    rm -rf -- "$MATHLAND_STAGE_ROOT"
  fi
}
trap cleanup_mathland_stage EXIT

mkdir -p "$MATHLAND_PROJECT_ROOT/dist"
bash "$MATHLAND_PROJECT_ROOT/scripts/android/bootstrap_sdk.sh"
env npm --prefix "$MATHLAND_PROJECT_ROOT" run verify:toolchain
"$MATHLAND_PROJECT_ROOT/scripts/android/build_secure_credentials_plugin.sh"
bash "$MATHLAND_PROJECT_ROOT/scripts/android/stage_project.sh" \
  "$MATHLAND_PROJECT_ROOT" \
  "$MATHLAND_STAGE_ROOT"
if [ -n "${MATHLAND_SUPABASE_URL:-}" ] || [ -n "${MATHLAND_SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  if [ -z "${MATHLAND_SUPABASE_URL:-}" ] || [ -z "${MATHLAND_SUPABASE_PUBLISHABLE_KEY:-}" ]; then
    echo "Both public Supabase configuration values must be provided together" >&2
    exit 1
  fi
  MATHLAND_CLOUD_CONFIG_PATH="$MATHLAND_STAGE_ROOT/resources/config/cloud_public.json" \
  MATHLAND_RELEASE_BUILD=1 \
    "$MATHLAND_PROJECT_ROOT/scripts/android/write_public_cloud_config.sh"
fi
mkdir -p "$MATHLAND_STAGE_ROOT/dist"
GRADLE_OPTS="$MATHLAND_GRADLE_OPTS" "$MATHLAND_GODOT_BIN" \
  --headless \
  --path "$MATHLAND_STAGE_ROOT" \
  --install-android-build-template \
  --export-debug "Android Debug" \
  "$MATHLAND_STAGED_APK"
cp "$MATHLAND_STAGED_APK" "$MATHLAND_DEBUG_APK"
"$MATHLAND_PROJECT_ROOT/scripts/android/inspect_manifest.sh" "$MATHLAND_DEBUG_APK"
