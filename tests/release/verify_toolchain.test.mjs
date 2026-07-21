import test from "node:test";
import assert from "node:assert/strict";

import { validateProbe } from "../../scripts/ci/verify_toolchain.mjs";

const valid = {
  godotVersion: "4.7.1.stable.official.a13da4feb",
  javaVersion: "17.0.19",
  platforms: ["android-35"],
  buildTools: ["35.0.1"],
  executables: { adb: true, apksigner: true, zipalign: true, aapt2: true },
};

test("accepts the exact release toolchain", () => {
  assert.deepEqual(validateProbe(valid), []);
});

test("reports every release-blocking mismatch in stable order", () => {
  const findings = validateProbe({
    ...valid,
    godotVersion: "4.7.0.stable.official",
    javaVersion: "21.0.2",
    platforms: ["android-36"],
    buildTools: ["36.0.0"],
    executables: { adb: true, apksigner: false, zipalign: false, aapt2: true },
  });
  assert.deepEqual(findings, [
    "Godot must be 4.7.1; found 4.7.0.stable.official",
    "Java major version must be 17; found 21.0.2",
    "Android platform android-35 is missing",
    "Android build-tools 35.0.1 is missing",
    "Android executable apksigner is missing",
    "Android executable zipalign is missing",
  ]);
});

test("malformed probe data is reported instead of throwing", () => {
  assert.deepEqual(validateProbe({}), [
    "Godot must be 4.7.1; found unknown",
    "Java major version must be 17; found unknown",
    "Android platform android-35 is missing",
    "Android build-tools 35.0.1 is missing",
    "Android executable adb is missing",
    "Android executable apksigner is missing",
    "Android executable zipalign is missing",
    "Android executable aapt2 is missing",
  ]);
});
