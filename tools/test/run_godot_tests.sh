#!/usr/bin/env bash
set -euo pipefail

suite=${1:-all}
case "$suite" in
	all|unit|scene|integration|content) ;;
	*)
		echo "invalid Godot test suite: $suite" >&2
		exit 2
		;;
esac

godot_bin=${GODOT_BIN:-godot}
output_log=$(mktemp "${TMPDIR:-/tmp}/mathland-godot-tests.XXXXXX")
trap 'rm -f "$output_log"' EXIT

set +e
"$godot_bin" --headless --path . --script res://tests/run_all.gd -- --suite "$suite" 2>&1 | tee "$output_log"
godot_status=${PIPESTATUS[0]}
set -e

if grep -Eq 'SCRIPT ERROR:|^ERROR: Failed to (load|instantiate) script' "$output_log"; then
	echo "Godot emitted a script load or runtime error" >&2
	exit 1
fi

if [[ $godot_status -ne 0 ]]; then
	exit "$godot_status"
fi

if ! grep -Eq '^RESULT PASS tests=[0-9]+$' "$output_log"; then
	echo "Godot test runner did not report a successful terminal result" >&2
	exit 1
fi
