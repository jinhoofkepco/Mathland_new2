#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
godot_bin=${GODOT_BIN:-godot}
archive_root=$(mktemp -d "${TMPDIR:-/tmp}/mathland-fresh-archive.XXXXXX")
trap 'rm -rf -- "$archive_root"' EXIT

git -C "$repo_root" archive HEAD | tar -x -C "$archive_root"
if [ -e "$archive_root/.godot" ]; then
	echo "fresh archive unexpectedly contains .godot cache" >&2
	exit 1
fi

suites=("${@:-unit}")
for suite in "${suites[@]}"; do
	(
		cd "$archive_root"
		GODOT_BIN="$godot_bin" ./tools/test/run_godot_tests.sh "$suite"
	)
done

echo "fresh archive Godot tests passed: ${suites[*]}"
