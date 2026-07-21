import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/android/inspect_manifest.sh");
const validManifest = `
<manifest package="com.jinhoofkepco.mathland" android:versionCode="1" android:versionName="1.0.0">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35" />
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.VIBRATE" />
  <application android:allowBackup="false" />
</manifest>`;

function runInspection({ manifest = validManifest, files = "/lib/arm64-v8a/libgodot_android.so" } = {}) {
  const fixtureRoot = mkdtempSync(join(tmpdir(), "mathland-manifest-"));
  try {
    const apk = join(fixtureRoot, "MathLand fixture.apk");
    const analyzer = join(fixtureRoot, "fake-apkanalyzer.mjs");
    writeFileSync(apk, "fixture");
    writeFileSync(
      analyzer,
      `#!/usr/bin/env node
const [group, action, apkPath] = process.argv.slice(2);
if (!apkPath || !apkPath.endsWith("MathLand fixture.apk")) process.exit(9);
if (!process.env.APKANALYZER_OPTS?.includes("/cmdline-tools/latest")) process.exit(7);
if (group === "manifest" && action === "print") process.stdout.write(process.env.FAKE_MANIFEST);
else if (group === "files" && action === "list") process.stdout.write(process.env.FAKE_FILES);
else process.exit(8);
`,
    );
    chmodSync(analyzer, 0o755);
    return spawnSync("bash", [script, apk], {
      encoding: "utf8",
      env: { ...process.env, APKANALYZER_BIN: analyzer, FAKE_MANIFEST: manifest, FAKE_FILES: files },
      timeout: 5_000,
    });
  } finally {
    rmSync(fixtureRoot, { recursive: true, force: true });
  }
}

test("accepts the exact private ARM64 manifest policy", () => {
  const result = runInspection();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /PASS: Android manifest and ABI policy/);
});

test("rejects dangerous permissions", () => {
  const result = runInspection({
    manifest: validManifest.replace(
      "</manifest>",
      '<uses-permission android:name="android.permission.RECORD_AUDIO" /></manifest>',
    ),
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /forbidden camera or microphone/);
});

test("rejects non-ARM64 or missing ARM64 native libraries", () => {
  const wrongAbi = runInspection({ files: "/lib/x86_64/libgodot_android.so" });
  assert.equal(wrongAbi.status, 1);
  assert.match(wrongAbi.stderr, /arm64-v8a library missing/);

  const mixedAbi = runInspection({
    files: "/lib/arm64-v8a/libgodot_android.so\n/lib/x86/libgodot_android.so",
  });
  assert.equal(mixedAbi.status, 1);
  assert.match(mixedAbi.stderr, /non-ARM64 native library present/);
});

test("rejects missing privacy and SDK declarations", () => {
  const backup = runInspection({ manifest: validManifest.replace('android:allowBackup="false"', "") });
  assert.equal(backup.status, 1);
  assert.match(backup.stderr, /backup disabled/);

  const target = runInspection({ manifest: validManifest.replace('android:targetSdkVersion="35"', 'android:targetSdkVersion="34"') });
  assert.equal(target.status, 1);
  assert.match(target.stderr, /target SDK 35/);
});
