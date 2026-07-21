#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: inspect_manifest.sh <apk>" >&2
  exit 2
fi

MATHLAND_APK_PATH="$1"
if [ ! -s "$MATHLAND_APK_PATH" ]; then
  echo "APK is missing or empty: $MATHLAND_APK_PATH" >&2
  exit 1
fi

MATHLAND_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$MATHLAND_SDK_ROOT" ]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required" >&2
  exit 1
fi
MATHLAND_APKANALYZER_BIN="${APKANALYZER_BIN:-}"
if [ -z "$MATHLAND_APKANALYZER_BIN" ] && [ -n "$MATHLAND_SDK_ROOT" ]; then
  MATHLAND_APKANALYZER_BIN="$MATHLAND_SDK_ROOT/cmdline-tools/latest/bin/apkanalyzer"
fi
if [ ! -x "$MATHLAND_APKANALYZER_BIN" ]; then
  MATHLAND_APKANALYZER_BIN="/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/apkanalyzer"
fi
if [ ! -x "$MATHLAND_APKANALYZER_BIN" ]; then
  echo "apkanalyzer is unavailable; set APKANALYZER_BIN" >&2
  exit 1
fi

MATHLAND_APKANALYZER_OPTS="${APKANALYZER_OPTS:-} -Dcom.android.sdklib.toolsdir=$MATHLAND_SDK_ROOT/cmdline-tools/latest"
MATHLAND_MANIFEST="$(
  APKANALYZER_OPTS="$MATHLAND_APKANALYZER_OPTS" \
    "$MATHLAND_APKANALYZER_BIN" manifest print "$MATHLAND_APK_PATH"
)"
MATHLAND_FILES="$(
  APKANALYZER_OPTS="$MATHLAND_APKANALYZER_OPTS" \
    "$MATHLAND_APKANALYZER_BIN" files list "$MATHLAND_APK_PATH"
)"
MATHLAND_NORMALIZED_FILES="$(
  perl -ne '
    chomp;
    s{\r$}{};
    s{\\}{/}g;
    s{/+}{/}g;
    s{^/+}{};
    1 while s{^\./}{};
    print "$_\n" if length;
  ' <<<"$MATHLAND_FILES"
)"

if rg --quiet --pcre2 '(?:^|/)\.\.(?:/|$)' <<<"$MATHLAND_NORMALIZED_FILES"; then
  echo "APK policy failed: unsafe parent path component present" >&2
  exit 1
fi

require_manifest() {
  local pattern="$1"
  local description="$2"
  if ! rg --quiet --pcre2 "$pattern" <<<"$MATHLAND_MANIFEST"; then
    echo "Manifest policy failed: $description" >&2
    exit 1
  fi
}

reject_manifest() {
  local pattern="$1"
  local description="$2"
  if rg --quiet --pcre2 "$pattern" <<<"$MATHLAND_MANIFEST"; then
    echo "Manifest policy failed: forbidden $description" >&2
    exit 1
  fi
}

require_manifest 'package="com\.jinhoofkepco\.mathland"' "package id"
require_manifest 'android:versionCode="1"' "version code 1"
require_manifest 'android:versionName="1\.0\.0"' "version name 1.0.0"
require_manifest 'android:minSdkVersion="24"' "minimum SDK 24"
require_manifest 'android:targetSdkVersion="35"' "target SDK 35"
require_manifest 'android:allowBackup="false"' "backup disabled"
require_manifest 'android\.permission\.INTERNET' "internet permission"
require_manifest 'android\.permission\.VIBRATE' "vibrate permission"

reject_manifest 'android\.permission\.(CAMERA|RECORD_AUDIO)' "camera or microphone permission"
reject_manifest 'android\.permission\.(ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|ACCESS_BACKGROUND_LOCATION)' "location permission"
reject_manifest 'android\.permission\.(READ_CONTACTS|WRITE_CONTACTS|GET_ACCOUNTS)' "contacts or accounts permission"
reject_manifest 'android\.permission\.(READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_[A-Z_]+)' "storage or media permission"
reject_manifest '(com\.google\.android\.gms\.permission\.AD_ID|android\.permission\.ACCESS_ADSERVICES_AD_ID)' "advertising identifier permission"

MATHLAND_PERMISSIONS="$(
  perl -0ne '
    while (/<uses-permission(?:-sdk-\d+)?\b[^>]*\bandroid:name="([^"]+)"/sg) {
      print "$1\n";
    }
  ' <<<"$MATHLAND_MANIFEST" | LC_ALL=C sort
)"
MATHLAND_EXPECTED_PERMISSIONS=$'android.permission.INTERNET\nandroid.permission.VIBRATE'
if [ "$MATHLAND_PERMISSIONS" != "$MATHLAND_EXPECTED_PERMISSIONS" ]; then
  echo "Manifest policy failed: permission allowlist must be exactly INTERNET and VIBRATE" >&2
  echo "Found permissions:" >&2
  printf '%s\n' "$MATHLAND_PERMISSIONS" >&2
  exit 1
fi

if ! rg --quiet '^lib/arm64-v8a/[^/]+\.so$' <<<"$MATHLAND_NORMALIZED_FILES"; then
  echo "APK policy failed: arm64-v8a shared library missing" >&2
  exit 1
fi
if rg --quiet --pcre2 '^lib/(?!arm64-v8a(?:/|$))[^/]+/' <<<"$MATHLAND_NORMALIZED_FILES"; then
  echo "APK policy failed: non-ARM64 native library present" >&2
  exit 1
fi
if rg --quiet --pcre2 '(?:^|/)(?:\.git|\.github|node_modules|tests|docs|reports|coverage|playwright-report|test-results|web|supabase|packages|scripts|tools|dist)(?:/|$)|^assets/(?:[^/]+/)*android(?:/|$)|(?:^|/)(?:package(?:-lock)?\.json|\.env(?:\.[^/]*)?|\.DS_Store|[^/]*\.(?:keystore|jks|p12))$' <<<"$MATHLAND_NORMALIZED_FILES"; then
  echo "APK policy failed: host development artifact present" >&2
  exit 1
fi

echo "PASS: Android manifest and ABI policy"
