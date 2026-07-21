#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MATHLAND_REPO_ROOT="$(cd "$MATHLAND_SCRIPT_DIR/../.." && pwd)"
MATHLAND_CONFIG_PATH="${MATHLAND_CLOUD_CONFIG_PATH:-$MATHLAND_REPO_ROOT/resources/config/cloud_public.json}"
MATHLAND_RELEASE_MODE="${MATHLAND_RELEASE_BUILD:-1}"
MATHLAND_URL="${MATHLAND_SUPABASE_URL:-}"
MATHLAND_PUBLIC_KEY="${MATHLAND_SUPABASE_PUBLISHABLE_KEY:-}"

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

[[ -n "$MATHLAND_URL" ]] || fail "MATHLAND_SUPABASE_URL is required"
[[ -n "$MATHLAND_PUBLIC_KEY" ]] || fail "MATHLAND_SUPABASE_PUBLISHABLE_KEY is required"
[[ "$MATHLAND_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$ ]] || fail "Supabase URL must be a simple HTTPS origin"
[[ "$MATHLAND_PUBLIC_KEY" =~ ^sb_publishable_[A-Za-z0-9._-]+$ ]] || fail "publishable key has an invalid format"

MATHLAND_URL_LOWER="$(printf '%s' "$MATHLAND_URL" | tr '[:upper:]' '[:lower:]')"
MATHLAND_KEY_LOWER="$(printf '%s' "$MATHLAND_PUBLIC_KEY" | tr '[:upper:]' '[:lower:]')"
[[ "$MATHLAND_KEY_LOWER" != *service_role* ]] || fail "service-role keys are forbidden"
if [[ "$MATHLAND_RELEASE_MODE" != "0" ]]; then
  [[ "$MATHLAND_URL_LOWER" != https://localhost* ]] || fail "localhost is forbidden in release configuration"
  [[ "$MATHLAND_URL_LOWER" != https://127.* ]] || fail "loopback is forbidden in release configuration"
fi

mkdir -p "$(dirname "$MATHLAND_CONFIG_PATH")"
MATHLAND_TEMP_PATH="$(mktemp "${MATHLAND_CONFIG_PATH}.tmp.XXXXXX")"
trap 'rm -f "$MATHLAND_TEMP_PATH"' EXIT
printf '{\n  "supabase_url": "%s",\n  "publishable_key": "%s"\n}\n' \
  "${MATHLAND_URL%/}" "$MATHLAND_PUBLIC_KEY" >"$MATHLAND_TEMP_PATH"
mv "$MATHLAND_TEMP_PATH" "$MATHLAND_CONFIG_PATH"
trap - EXIT
echo "Wrote public cloud configuration to $MATHLAND_CONFIG_PATH"
