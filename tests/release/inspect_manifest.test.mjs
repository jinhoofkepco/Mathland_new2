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

test("accepts generated Android and Godot runtime metadata", () => {
  const result = runInspection({
    files: [
      "/lib/arm64-v8a/libgodot_android.so",
      "/META-INF/com/android/build/gradle/app-metadata.properties",
      "/assets/.godot/exported/fixture/export-app_shell.scn",
    ].join("\n"),
  });
  assert.equal(result.status, 0, result.stderr);
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

test("rejects every permission outside the exact INTERNET and VIBRATE allowlist", () => {
  const additions = [
    '<uses-permission android:name="android.permission.READ_SMS" />',
    '<uses-permission\n android:name="android.permission.READ_PHONE_STATE" />',
    '<uses-permission-sdk-23 android:name="com.example.UNEXPECTED" />',
  ];
  for (const addition of additions) {
    const result = runInspection({
      manifest: validManifest.replace("</manifest>", `${addition}</manifest>`),
    });
    assert.equal(result.status, 1, `accepted ${addition}`);
    assert.match(result.stderr, /permission allowlist/, result.stderr);
  }
});

test("rejects non-ARM64 or missing ARM64 native libraries", () => {
  const wrongAbi = runInspection({ files: "/lib/x86_64/libgodot_android.so" });
  assert.equal(wrongAbi.status, 1);
  assert.match(wrongAbi.stderr, /arm64-v8a shared library missing/);

  const mixedAbi = runInspection({
    files: "/lib/arm64-v8a/libgodot_android.so\n/lib/x86/libgodot_android.so",
  });
  assert.equal(mixedAbi.status, 1);
  assert.match(mixedAbi.stderr, /non-ARM64 native library present/);

  const riscvAbi = runInspection({
    files: "/lib/arm64-v8a/libgodot_android.so\n/lib/riscv64/libunexpected.so",
  });
  assert.equal(riscvAbi.status, 1);
  assert.match(riscvAbi.stderr, /non-ARM64 native library present/);
});

test("requires at least one actual ARM64 shared object", () => {
  for (const files of ["/lib/arm64-v8a/", "/lib/arm64-v8a/readme.txt"]) {
    const result = runInspection({ files });
    assert.equal(result.status, 1, `accepted ${files}`);
    assert.match(result.stderr, /arm64-v8a shared library missing/);
  }
});

test("rejects host development artifacts from packaged assets", () => {
  const forbidden = [
    "/assets/package.json",
    "/assets/package-lock.json",
    "/assets/node_modules/example/index.js",
    "/assets/tools/private_generator.mjs",
    "/assets/.env.local",
    "/assets/release.keystore",
    "/assets/runtime/private/.git/config",
    "/assets/runtime/private/.github/workflows/ci.yml",
    "/assets/runtime/private/.env",
    "/assets/runtime/private/.env.production",
    "/assets/runtime/private/.DS_Store",
    "/assets/runtime/private/package.json",
    "/assets/runtime/private/package-lock.json",
    "/assets/runtime/private/keys/release.jks",
    "/assets/runtime/private/keys/release.keystore",
    "/assets/runtime/private/keys/release.p12",
    "/assets/runtime/private/android/build.bin",
    "/assets/runtime/private/coverage/report.json",
    "/assets/runtime/private/dist/app.js",
    "/assets/runtime/private/docs/plan.md",
    "/assets/runtime/private/node_modules/example/index.js",
    "/assets/runtime/private/packages/contracts/package.json",
    "/assets/runtime/private/playwright-report/index.html",
    "/assets/runtime/private/reports/test.xml",
    "/assets/runtime/private/scripts/build.sh",
    "/assets/runtime/private/supabase/config.toml",
    "/assets/runtime/private/test-results/result.json",
    "/assets/runtime/private/tests/test.gd",
    "/assets/runtime/private/tools/private_generator.mjs",
    "/assets/runtime/private/web/index.html",
    "//assets//runtime//private//.env.staging",
    "./assets/runtime/private/keys/release.jks",
    String.raw`\assets\runtime\private\keys\release.keystore`,
  ];
  for (const path of forbidden) {
    const result = runInspection({
      files: `/lib/arm64-v8a/libgodot_android.so\n${path}`,
    });
    assert.equal(result.status, 1, `accepted ${path}`);
    assert.match(result.stderr, /host development artifact/);
  }
});

test("rejects environment and signing-key names used as path components", () => {
  const forbidden = [
    "/assets/runtime/private/.env.local/secret.txt",
    "/assets/runtime/private/release.jks/secret.txt",
  ];
  for (const path of forbidden) {
    const result = runInspection({
      files: `/lib/arm64-v8a/libgodot_android.so\n${path}`,
    });
    assert.equal(result.status, 1, `accepted ${path}`);
    assert.match(result.stderr, /host development artifact/);
  }
});

test("rejects missing privacy and SDK declarations", () => {
  const backup = runInspection({ manifest: validManifest.replace('android:allowBackup="false"', "") });
  assert.equal(backup.status, 1);
  assert.match(backup.stderr, /backup disabled/);

  const target = runInspection({ manifest: validManifest.replace('android:targetSdkVersion="35"', 'android:targetSdkVersion="34"') });
  assert.equal(target.status, 1);
  assert.match(target.stderr, /target SDK 35/);
});
