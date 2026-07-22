import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const apk = resolve("dist/MathLand-debug-arm64.apk");
const exportScript = resolve("scripts/android/export_debug.sh");
const resourceSelectors = {
  app_shell: /-app_shell\.scn$/,
  effect_burst: /-effect_burst\.scn$/,
  tactile_button: /-tactile_button\.scn$/,
  sparse_pck: /^assets\/assets\.sparsepck$/,
};

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: resolve("."),
    encoding: options.encoding ?? "utf8",
    maxBuffer: 8 * 1024 * 1024,
    timeout: options.timeout ?? 120_000,
    ...options,
  });
  assert.equal(result.status, 0, `${command} failed:\n${result.stderr || result.stdout}`);
  return result.stdout;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function snapshotExport() {
  const listing = run("unzip", ["-Z1", apk]).trim().split("\n").sort();
  const resources = {};
  for (const [name, selector] of Object.entries(resourceSelectors)) {
    const entries = listing.filter((entry) => selector.test(entry));
    assert.equal(entries.length, 1, `${name} matched ${entries.join(", ") || "nothing"}`);
    const contents = run("unzip", ["-p", apk, entries[0]], { encoding: null });
    resources[name] = { entry: entries[0], sha256: sha256(contents) };
  }
  return {
    apkSha256: sha256(readFileSync(apk)),
    listingSha256: sha256(`${listing.join("\n")}\n`),
    resources,
  };
}

test("consecutive clean-stage exports preserve Godot scene and sparse PCK bytes", { timeout: 300_000 }, (t) => {
  const statusBefore = run("git", ["status", "--porcelain=v1", "-uall"]);
  run(exportScript, [], { timeout: 150_000 });
  const first = snapshotExport();
  run(exportScript, [], { timeout: 150_000 });
  const second = snapshotExport();
  const statusAfter = run("git", ["status", "--porcelain=v1", "-uall"]);

  assert.equal(statusAfter, statusBefore, "export mutated the source checkout");
  assert.equal(second.apkSha256, first.apkSha256, "complete debug APK bytes changed");
  assert.equal(second.listingSha256, first.listingSha256, "APK resource listing changed");
  assert.deepEqual(second.resources, first.resources);
  t.diagnostic(`APK SHA-256 ${first.apkSha256}`);
  for (const [name, evidence] of Object.entries(first.resources)) {
    t.diagnostic(`${name} SHA-256 ${evidence.sha256}`);
  }
});
