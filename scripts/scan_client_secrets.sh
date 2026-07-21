#!/usr/bin/env bash
set -euo pipefail

MATHLAND_SCAN_SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MATHLAND_SCAN_REPO_ROOT="$(CDPATH= cd -- "$MATHLAND_SCAN_SCRIPT_DIR/.." && pwd)"
MATHLAND_SCAN_TARGET="${1:-$MATHLAND_SCAN_REPO_ROOT/web/dist}"
MATHLAND_RG_BIN="${MATHLAND_RG_BIN:-rg}"

if ! command -v "$MATHLAND_RG_BIN" >/dev/null 2>&1; then
  echo "FAIL: ripgrep is required for the client bundle scan" >&2
  exit 1
fi

if [[ ! -e "$MATHLAND_SCAN_TARGET" ]]; then
  echo "FAIL: client bundle scan target does not exist: $MATHLAND_SCAN_TARGET" >&2
  exit 1
fi

MATHLAND_SECRET_PATTERN='sb_secret_[A-Za-z0-9._-]{8,}|service[_-]?role[._-][A-Za-z0-9._-]{8,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:sk|rk|pk)-[A-Za-z0-9_-]{20,}'
MATHLAND_TOKEN_PATTERN='eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}'
MATHLAND_DEVELOPMENT_HOST_PATTERN='https?://(?:localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0|\[::1\])(?::[0-9]+)?'

MATHLAND_RG_STATUS=0
MATHLAND_SECRET_FINDINGS="$("$MATHLAND_RG_BIN" --files-with-matches --hidden --no-ignore-vcs --pcre2 \
  --glob '!*.license' \
  --glob '!*.md' \
  --glob '!*.map' \
  -e "$MATHLAND_SECRET_PATTERN" \
  "$MATHLAND_SCAN_TARGET")" || MATHLAND_RG_STATUS=$?
if [[ "$MATHLAND_RG_STATUS" -gt 1 ]]; then
  echo "FAIL: ripgrep could not inspect the client bundle" >&2
  exit 1
fi

MATHLAND_RG_STATUS=0
MATHLAND_FIRST_PARTY_FINDINGS="$("$MATHLAND_RG_BIN" --files-with-matches --hidden --no-ignore-vcs --pcre2 \
  --glob '!*.license' \
  --glob '!*.md' \
  --glob '!*.map' \
  --glob '!*vendor*' \
  -e "$MATHLAND_TOKEN_PATTERN" \
  -e "$MATHLAND_DEVELOPMENT_HOST_PATTERN" \
  "$MATHLAND_SCAN_TARGET")" || MATHLAND_RG_STATUS=$?
if [[ "$MATHLAND_RG_STATUS" -gt 1 ]]; then
  echo "FAIL: ripgrep could not inspect the first-party client bundle" >&2
  exit 1
fi
MATHLAND_FINDINGS="$(printf '%s\n%s\n' "$MATHLAND_SECRET_FINDINGS" "$MATHLAND_FIRST_PARTY_FINDINGS" | sed '/^$/d' | sort -u)"

if [[ -n "$MATHLAND_FINDINGS" ]]; then
  echo "FAIL: privileged or development-only material was found in client files:" >&2
  while IFS= read -r MATHLAND_FINDING; do
    [[ -n "$MATHLAND_FINDING" ]] && echo "  $MATHLAND_FINDING" >&2
  done <<<"$MATHLAND_FINDINGS"
  exit 1
fi

echo "PASS: client files contain only publishable cloud configuration"
