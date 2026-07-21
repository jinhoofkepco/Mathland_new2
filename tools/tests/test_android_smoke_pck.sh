#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
godot_bin=${GODOT_BIN:-godot}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/mathland-smoke-pck.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

import_log="$test_root/import.log"
export_log="$test_root/export.log"
pck_path="$test_root/android-smoke.pck"

"$godot_bin" --headless --editor --path "$repo_root" --quit 2>&1 | tee "$import_log"
if grep -Eq 'SCRIPT ERROR:|^ERROR:|Failed to import|Import process failed' "$import_log"; then
	echo "Godot emitted an import error before Android Smoke export" >&2
	exit 1
fi
"$godot_bin" --headless --path "$repo_root" \
	--export-pack "Android Smoke" "$pck_path" 2>&1 | tee "$export_log"

node --input-type=module - \
	"$repo_root/assets/asset-manifest.json" "$export_log" "$pck_path" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";

const [, , manifestPath, logPath, pckPath] = process.argv;
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const exportLog = readFileSync(logPath, "utf8").replaceAll(/\x1b\[[0-9;]*m/g, "");
const saved = new Set(
  [...exportLog.matchAll(/res:\/\/([^\r\n]+)/g)].map((match) => match[1].trim()),
);

assert.ok(statSync(pckPath).size > 0, "Android Smoke PCK is empty");
assert.equal(
  [...saved].some((path) => path.startsWith("assets/source/")),
  false,
  `provenance-only source asset entered PCK:\n${[...saved]
    .filter((path) => path.startsWith("assets/source/"))
    .join("\n")}`,
);

for (const asset of manifest.assets.filter((candidate) => candidate.release === true)) {
  assert.ok(
    saved.has(asset.path) || saved.has(`${asset.path}.import`),
    `release asset missing from Android Smoke PCK listing: ${asset.id} (${asset.path})`,
  );
}

console.log(
  `Android Smoke PCK policy passed: ${manifest.assets.filter((asset) => asset.release).length} release assets, ${statSync(pckPath).size} bytes`,
);
NODE
