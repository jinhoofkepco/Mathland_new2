#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_BIN="$(command -v supabase)"
elif [[ -x "$REPO_ROOT/node_modules/.bin/supabase" ]]; then
  SUPABASE_BIN="$REPO_ROOT/node_modules/.bin/supabase"
else
  echo "BLOCKED: Supabase CLI is required. Install it, then rerun ./scripts/test_sql.sh." >&2
  exit 2
fi

cd "$REPO_ROOT"
"$SUPABASE_BIN" db start
"$SUPABASE_BIN" db reset --local --no-seed
"$SUPABASE_BIN" test db
