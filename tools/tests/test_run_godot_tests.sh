#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner="$repo_root/tools/test/run_godot_tests.sh"
test_temp=$(mktemp -d "${TMPDIR:-/tmp}/mathland-runner-test.XXXXXX")
trap 'rm -rf -- "$test_temp"' EXIT

fake_godot="$test_temp/fake-godot"
printf '%s\n' '#!/usr/bin/env bash' > "$fake_godot"
printf '%s\n' 'printf "%s\n" "$*" >> "${FAKE_CALL_LOG:?}"' >> "$fake_godot"
printf '%s\n' 'if [[ " $* " == *" --editor "* ]]; then' >> "$fake_godot"
printf '%s\n' '  case "${FAKE_MODE:-success}" in' >> "$fake_godot"
printf '%s\n' '    import_error) printf "%s\n" "ERROR: Failed to import res://broken.svg" >&2; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '    import_failure) printf "%s\n" "Import process failed" >&2; exit 9 ;;' >> "$fake_godot"
printf '%s\n' '    *) printf "%s\n" "IMPORT OK"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '  esac' >> "$fake_godot"
printf '%s\n' 'fi' >> "$fake_godot"
printf '%s\n' 'case "${FAKE_MODE:-success}" in' >> "$fake_godot"
printf '%s\n' '  success) printf "%s\n" "RESULT PASS tests=1"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '  script_error) printf "%s\n" "SCRIPT ERROR: Invalid call" >&2; printf "%s\n" "RESULT PASS tests=1"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '  engine_failure) printf "%s\n" "RESULT FAIL tests=1"; exit 7 ;;' >> "$fake_godot"
printf '%s\n' '  no_result) printf "%s\n" "PASS res://tests/unit/test_example.gd"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' 'esac' >> "$fake_godot"
chmod u+x "$fake_godot"

call_log="$test_temp/calls.log"
: > "$call_log"
FAKE_CALL_LOG="$call_log" FAKE_MODE=success GODOT_BIN="$fake_godot" "$runner" unit >/dev/null

if [ "$(wc -l < "$call_log" | tr -d ' ')" -ne 2 ]; then
	echo "runner did not perform exactly one import before the test process" >&2
	exit 1
fi
if ! sed -n '1p' "$call_log" | grep -Eq -- '--headless .*--editor .*--path .*--quit'; then
	echo "runner did not make its first Godot call a deterministic headless import" >&2
	exit 1
fi
if ! sed -n '2p' "$call_log" | grep -Eq -- '--headless .*--path .*--script res://tests/run_all.gd'; then
	echo "runner did not start tests only after import" >&2
	exit 1
fi

: > "$call_log"
FAKE_CALL_LOG="$call_log" FAKE_MODE=success GODOT_BIN="$fake_godot" "$runner" content >/dev/null

if FAKE_CALL_LOG="$call_log" FAKE_MODE=import_error GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted an import error" >&2
	exit 1
fi

if FAKE_CALL_LOG="$call_log" FAKE_MODE=import_failure GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted a nonzero import process" >&2
	exit 1
fi

if FAKE_CALL_LOG="$call_log" FAKE_MODE=script_error GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted SCRIPT ERROR output" >&2
	exit 1
fi

if FAKE_CALL_LOG="$call_log" FAKE_MODE=engine_failure GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted a nonzero Godot exit" >&2
	exit 1
fi

if FAKE_CALL_LOG="$call_log" FAKE_MODE=no_result GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted output without a terminal result" >&2
	exit 1
fi

if FAKE_CALL_LOG="$call_log" GODOT_BIN="$fake_godot" "$runner" unknown >/dev/null 2>&1; then
	echo "runner accepted an unknown suite" >&2
	exit 1
fi

echo "runner self-test passed"
