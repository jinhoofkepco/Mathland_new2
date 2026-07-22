#!/usr/bin/env bash
set -euo pipefail

MATHLAND_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MATHLAND_WRITER="$MATHLAND_REPO_ROOT/scripts/android/write_public_cloud_config.sh"
MATHLAND_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$MATHLAND_TEST_DIR"' EXIT

MATHLAND_OUTPUT="$MATHLAND_TEST_DIR/cloud_public.json"
MATHLAND_SUPABASE_URL="https://mathland.example.supabase.co" \
MATHLAND_SUPABASE_PUBLISHABLE_KEY="sb_publishable_example" \
MATHLAND_CLOUD_CONFIG_PATH="$MATHLAND_OUTPUT" \
MATHLAND_RELEASE_BUILD=1 \
  "$MATHLAND_WRITER"

node -e '
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (JSON.stringify(value) !== JSON.stringify({supabase_url:"https://mathland.example.supabase.co",publishable_key:"sb_publishable_example"})) process.exit(1);
' "$MATHLAND_OUTPUT"

if MATHLAND_SUPABASE_URL="http://mathland.example" MATHLAND_SUPABASE_PUBLISHABLE_KEY="sb_publishable_example" MATHLAND_CLOUD_CONFIG_PATH="$MATHLAND_OUTPUT" "$MATHLAND_WRITER" >/dev/null 2>&1; then
  echo "FAIL: accepted non-HTTPS URL" >&2
  exit 1
fi
if MATHLAND_SUPABASE_URL="https://localhost" MATHLAND_SUPABASE_PUBLISHABLE_KEY="sb_publishable_example" MATHLAND_CLOUD_CONFIG_PATH="$MATHLAND_OUTPUT" MATHLAND_RELEASE_BUILD=1 "$MATHLAND_WRITER" >/dev/null 2>&1; then
  echo "FAIL: accepted release localhost" >&2
  exit 1
fi
if MATHLAND_SUPABASE_URL="https://mathland.example" MATHLAND_SUPABASE_PUBLISHABLE_KEY="service_role_not_public" MATHLAND_CLOUD_CONFIG_PATH="$MATHLAND_OUTPUT" "$MATHLAND_WRITER" >/dev/null 2>&1; then
  echo "FAIL: accepted service-role key" >&2
  exit 1
fi

rg -q 'write_public_cloud_config\.sh' "$MATHLAND_REPO_ROOT/scripts/android/export_debug.sh"
rg -q "exclude='resources/config/cloud_public\.json'" "$MATHLAND_REPO_ROOT/scripts/android/stage_project.sh"

echo "PASS: strict public cloud config writer"
