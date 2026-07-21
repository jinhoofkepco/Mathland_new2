#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$MATHLAND_SDK_ROOT" ]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required" >&2
  exit 1
fi

MATHLAND_SDKMANAGER_BIN="${SDKMANAGER_BIN:-}"
if [ -z "$MATHLAND_SDKMANAGER_BIN" ]; then
  MATHLAND_SDKMANAGER_BIN="$MATHLAND_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
fi
if [ ! -x "$MATHLAND_SDKMANAGER_BIN" ]; then
  MATHLAND_SDKMANAGER_BIN="/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager"
fi

MATHLAND_MISSING_PACKAGES=()
if [ ! -s "$MATHLAND_SDK_ROOT/platforms/android-35/android.jar" ]; then
  MATHLAND_MISSING_PACKAGES+=("platforms;android-35")
fi
if [ ! -s "$MATHLAND_SDK_ROOT/platforms/android-36/android.jar" ]; then
  MATHLAND_MISSING_PACKAGES+=("platforms;android-36")
fi
if [ ! -s "$MATHLAND_SDK_ROOT/build-tools/35.0.1/apksigner" ]; then
  MATHLAND_MISSING_PACKAGES+=("build-tools;35.0.1")
fi
if [ ! -s "$MATHLAND_SDK_ROOT/build-tools/36.1.0/aapt2" ]; then
  MATHLAND_MISSING_PACKAGES+=("build-tools;36.1.0")
fi

if [ "${#MATHLAND_MISSING_PACKAGES[@]}" -gt 0 ]; then
  if [ ! -x "$MATHLAND_SDKMANAGER_BIN" ]; then
    echo "sdkmanager is required to install pinned Android SDK packages" >&2
    exit 1
  fi
  "$MATHLAND_SDKMANAGER_BIN" \
    "--sdk_root=$MATHLAND_SDK_ROOT" \
    "${MATHLAND_MISSING_PACKAGES[@]}"
fi

MATHLAND_REQUIRED_FILES=(
  "$MATHLAND_SDK_ROOT/platforms/android-35/android.jar"
  "$MATHLAND_SDK_ROOT/platforms/android-36/android.jar"
  "$MATHLAND_SDK_ROOT/build-tools/35.0.1/apksigner"
  "$MATHLAND_SDK_ROOT/build-tools/36.1.0/aapt2"
)
for MATHLAND_REQUIRED_FILE in "${MATHLAND_REQUIRED_FILES[@]}"; do
  if [ ! -s "$MATHLAND_REQUIRED_FILE" ]; then
    echo "Pinned Android SDK package did not provide $MATHLAND_REQUIRED_FILE" >&2
    exit 1
  fi
done

echo "PASS: Android SDK target 35 and Godot compile SDK 36 are installed"
