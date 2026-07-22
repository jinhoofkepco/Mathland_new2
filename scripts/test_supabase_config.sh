#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../supabase/config.toml"

if ! grep -Eq '^[[:space:]]*enable_anonymous_sign_ins[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CONFIG_PATH"; then
  echo "FAIL: Supabase anonymous device sign-in must be enabled." >&2
  exit 1
fi

if ! awk '
  $0 == "[functions.activate-publications]" { in_worker = 1; found_worker = 1; next }
  in_worker && /^\[/ { in_worker = 0 }
  in_worker && /^[[:space:]]*verify_jwt[[:space:]]*=[[:space:]]*false[[:space:]]*$/ {
    found_setting = 1
  }
  END { exit !(found_worker && found_setting) }
' "$CONFIG_PATH"; then
  echo "FAIL: scheduled activation function must disable gateway JWT verification." >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*enable_signup[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CONFIG_PATH"; then
  echo "FAIL: Supabase guardian email sign-up must be enabled." >&2
  exit 1
fi

echo "PASS: Supabase anonymous device sign-in is enabled."
echo "PASS: scheduled activation uses its dedicated worker authentication boundary."
echo "PASS: Supabase guardian email sign-up is enabled."
