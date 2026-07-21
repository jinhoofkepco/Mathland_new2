#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../supabase/config.toml"

if ! grep -Eq '^[[:space:]]*enable_anonymous_sign_ins[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$CONFIG_PATH"; then
  echo "FAIL: Supabase anonymous device sign-in must be enabled." >&2
  exit 1
fi

echo "PASS: Supabase anonymous device sign-in is enabled."
