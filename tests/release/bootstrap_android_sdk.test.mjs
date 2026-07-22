import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/android/bootstrap_sdk.sh");

function makeFixture() {
  const root = mkdtempSync(join(tmpdir(), "mathland-sdk-bootstrap-"));
  const sdk = join(root, "sdk");
  const log = join(root, "sdkmanager.log");
  const sdkmanager = join(root, "sdkmanager");
  mkdirSync(join(sdk, "platforms", "android-35"), { recursive: true });
  mkdirSync(join(sdk, "build-tools", "35.0.1"), { recursive: true });
  writeFileSync(join(sdk, "platforms", "android-35", "android.jar"), "target");
  writeFileSync(join(sdk, "build-tools", "35.0.1", "apksigner"), "signer");
  writeFileSync(
    sdkmanager,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$@" > "$FAKE_SDKMANAGER_LOG"
mkdir -p "$ANDROID_SDK_ROOT/platforms/android-36" "$ANDROID_SDK_ROOT/build-tools/36.1.0"
printf compile > "$ANDROID_SDK_ROOT/platforms/android-36/android.jar"
printf aapt > "$ANDROID_SDK_ROOT/build-tools/36.1.0/aapt2"
`,
  );
  chmodSync(sdkmanager, 0o755);
  return { root, sdk, log, sdkmanager };
}

test("installs only missing Godot compile SDK packages", () => {
  const fixture = makeFixture();
  try {
    const result = spawnSync("bash", [script], {
      encoding: "utf8",
      env: {
        ...process.env,
        ANDROID_HOME: fixture.sdk,
        ANDROID_SDK_ROOT: fixture.sdk,
        SDKMANAGER_BIN: fixture.sdkmanager,
        FAKE_SDKMANAGER_LOG: fixture.log,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    const args = readFileSync(fixture.log, "utf8").trim().split("\n");
    assert.deepEqual(args, [
      `--sdk_root=${fixture.sdk}`,
      "platforms;android-36",
      "build-tools;36.1.0",
    ]);
    assert.equal(readFileSync(join(fixture.sdk, "platforms/android-35/android.jar"), "utf8"), "target");
    assert.equal(readFileSync(join(fixture.sdk, "build-tools/35.0.1/apksigner"), "utf8"), "signer");
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});

test("does not invoke sdkmanager when every pinned package is present", () => {
  const fixture = makeFixture();
  try {
    mkdirSync(join(fixture.sdk, "platforms/android-36"), { recursive: true });
    mkdirSync(join(fixture.sdk, "build-tools/36.1.0"), { recursive: true });
    writeFileSync(join(fixture.sdk, "platforms/android-36/android.jar"), "compile");
    writeFileSync(join(fixture.sdk, "build-tools/36.1.0/aapt2"), "aapt");
    const result = spawnSync("bash", [script], {
      encoding: "utf8",
      env: {
        ...process.env,
        ANDROID_SDK_ROOT: fixture.sdk,
        SDKMANAGER_BIN: fixture.sdkmanager,
        FAKE_SDKMANAGER_LOG: fixture.log,
      },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.throws(() => readFileSync(fixture.log), /ENOENT/);
  } finally {
    rmSync(fixture.root, { recursive: true, force: true });
  }
});
