#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner="$repo_root/tools/test/run_godot_tests.sh"
test_temp=$(mktemp -d "${TMPDIR:-/tmp}/mathland-runner-test.XXXXXX")
trap 'rm -rf "$test_temp"' EXIT

fake_godot="$test_temp/fake-godot"
printf '%s\n' '#!/usr/bin/env bash' > "$fake_godot"
printf '%s\n' 'case "${FAKE_MODE:-success}" in' >> "$fake_godot"
printf '%s\n' '  success) printf "%s\n" "RESULT PASS tests=1"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '  script_error) printf "%s\n" "SCRIPT ERROR: Invalid call" >&2; printf "%s\n" "RESULT PASS tests=1"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' '  engine_failure) printf "%s\n" "RESULT FAIL tests=1"; exit 7 ;;' >> "$fake_godot"
printf '%s\n' '  no_result) printf "%s\n" "PASS res://tests/unit/test_example.gd"; exit 0 ;;' >> "$fake_godot"
printf '%s\n' 'esac' >> "$fake_godot"
chmod u+x "$fake_godot"

FAKE_MODE=success GODOT_BIN="$fake_godot" "$runner" unit >/dev/null
FAKE_MODE=success GODOT_BIN="$fake_godot" "$runner" content >/dev/null

if FAKE_MODE=script_error GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted SCRIPT ERROR output" >&2
	exit 1
fi

if FAKE_MODE=engine_failure GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted a nonzero Godot exit" >&2
	exit 1
fi

if FAKE_MODE=no_result GODOT_BIN="$fake_godot" "$runner" unit >/dev/null 2>&1; then
	echo "runner accepted output without a terminal result" >&2
	exit 1
fi

if GODOT_BIN="$fake_godot" "$runner" unknown >/dev/null 2>&1; then
	echo "runner accepted an unknown suite" >&2
	exit 1
fi

echo "runner self-test passed"
