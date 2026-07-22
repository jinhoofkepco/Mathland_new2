import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

function isIgnored(file) {
  const result = spawnSync("git", ["check-ignore", "--quiet", file], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.ok(result.status === 0 || result.status === 1, result.stderr);
  return result.status === 0;
}

test("ignores generated release and Gradle outputs without hiding sources", () => {
  for (const generated of [
    "android/plugins/secure_credentials/.gradle/8.11.1/cache.bin",
    "android/plugins/secure_credentials/.kotlin/sessions/compiler.salive",
    "android/plugins/secure_credentials/build/reports/report.html",
    "android/plugins/secure_credentials/secure_credentials/build/outputs/aar/plugin.aar",
    "reports/release/preflight.json",
  ]) {
    assert.equal(isIgnored(generated), true, `${generated} must be ignored`);
  }

  for (const source of [
    "android/plugins/secure_credentials/settings.gradle.kts",
    "android/plugins/secure_credentials/gradle/wrapper/gradle-wrapper.jar",
    "android/plugins/secure_credentials/secure_credentials/src/main/Foo.kt",
    "src/reports/source.gd",
  ]) {
    assert.equal(isIgnored(source), false, `${source} must remain trackable`);
  }
});
