import test from "node:test";
import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

import { probeToolchain, validateProbe } from "../../scripts/ci/verify_toolchain.mjs";

const EXACT_GODOT_VERSION = "4.7.1.stable.official.a13da4feb";
const scriptPath = fileURLToPath(new URL("../../scripts/ci/verify_toolchain.mjs", import.meta.url));
const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

const valid = {
  godotVersion: EXACT_GODOT_VERSION,
  javaVersion: "17.0.19",
  javacVersion: "17.0.19",
  platforms: ["android-35"],
  androidPlatformJarValid: true,
  buildTools: ["35.0.1"],
  executables: { adb: true, apksigner: true, zipalign: true, aapt2: true },
};

async function writeExecutable(file, body) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, `#!/usr/bin/env node\n${body}\n`, "utf8");
  await chmod(file, 0o755);
}

async function createToolchainFixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), "mathland-toolchain-"));
  t.after(async () => rm(root, { recursive: true, force: true }));

  const jdk = path.join(root, "jdk");
  const sdk = path.join(root, "sdk");
  const godot = path.join(root, "godot");
  const platformJar = path.join(sdk, "platforms", "android-35", "android.jar");
  const buildTools = path.join(sdk, "build-tools", "35.0.1");
  const tools = {
    adb: path.join(sdk, "platform-tools", "adb"),
    apksigner: path.join(buildTools, "apksigner"),
    zipalign: path.join(buildTools, "zipalign"),
    aapt2: path.join(buildTools, "aapt2"),
  };

  await writeExecutable(godot, `
if (process.argv[2] !== "--version") process.exit(9);
console.log("${EXACT_GODOT_VERSION}");
`);
  await writeExecutable(path.join(jdk, "bin", "java"), `
if (process.argv[2] !== "-version") process.exit(9);
console.error('openjdk version "17.0.19"');
`);
  await writeExecutable(path.join(jdk, "bin", "javac"), `
if (process.argv[2] !== "-version") process.exit(9);
console.log("javac 17.0.19");
`);
  await writeExecutable(path.join(jdk, "bin", "jar"), `
if (process.argv[2] !== "tf" || !process.argv[3]) process.exit(9);
process.exit(0);
`);
  await mkdir(path.dirname(platformJar), { recursive: true });
  await writeFile(platformJar, "PK\\u0003\\u0004fixture", "utf8");

  await writeExecutable(tools.adb, `
if (process.argv[2] !== "version") process.exit(9);
console.log("Android Debug Bridge version 1.0.41");
`);
  await writeExecutable(tools.apksigner, `
if (process.argv[2] !== "version") process.exit(9);
console.log("0.9");
`);
  await writeExecutable(tools.zipalign, `
if (process.argv.length !== 2) process.exit(9);
console.error("Zip alignment utility\\nUsage: zipalign");
process.exit(2);
`);
  await writeExecutable(tools.aapt2, `
if (process.argv[2] !== "version") process.exit(9);
console.log("Android Asset Packaging Tool (aapt) 2.19");
`);

  return {
    env: {
      ...process.env,
      GODOT_BIN: godot,
      JAVA_HOME: jdk,
      ANDROID_SDK_ROOT: sdk,
      ANDROID_HOME: sdk,
    },
    paths: { godot, jdk, sdk, platformJar, tools },
  };
}

test("accepts the exact, usable release toolchain", () => {
  assert.deepEqual(validateProbe(valid), []);
});

test("reports every release-blocking mismatch in stable order", () => {
  const findings = validateProbe({
    ...valid,
    godotVersion: "4.7.0.stable.official",
    javaVersion: "21.0.2",
    javacVersion: "21.0.2",
    platforms: ["android-36"],
    androidPlatformJarValid: false,
    buildTools: ["36.0.0"],
    executables: { adb: true, apksigner: false, zipalign: false, aapt2: true },
  });
  assert.deepEqual(findings, [
    `Godot must be ${EXACT_GODOT_VERSION}; found 4.7.0.stable.official`,
    "Java major version must be 17; found 21.0.2",
    "Javac major version must be 17; found 21.0.2",
    "Android platform android-35 is missing",
    "Android platform android-35/android.jar is missing or invalid",
    "Android build-tools 35.0.1 is missing",
    "Android executable apksigner is missing or unusable",
    "Android executable zipalign is missing or unusable",
  ]);
});

test("rejects prerelease, custom, and incomplete Godot version strings", () => {
  for (const godotVersion of ["4.7.1.rc1.custom", "4.7.1.", "4.7.1.stable.official.otherhash"]) {
    assert.deepEqual(validateProbe({ ...valid, godotVersion }), [
      `Godot must be ${EXACT_GODOT_VERSION}; found ${godotVersion}`,
    ]);
  }
});

test("malformed probe data is reported instead of throwing", () => {
  assert.deepEqual(validateProbe({}), [
    `Godot must be ${EXACT_GODOT_VERSION}; found unknown`,
    "Java major version must be 17; found unknown",
    "Javac major version must be 17; found unknown",
    "Android platform android-35 is missing",
    "Android platform android-35/android.jar is missing or invalid",
    "Android build-tools 35.0.1 is missing",
    "Android executable adb is missing or unusable",
    "Android executable apksigner is missing or unusable",
    "Android executable zipalign is missing or unusable",
    "Android executable aapt2 is missing or unusable",
  ]);
});

test("probes a complete fixture by executing every pinned tool", async (t) => {
  const fixture = await createToolchainFixture(t);

  const probe = await probeToolchain(fixture.env, { timeoutMs: 5_000 });

  assert.deepEqual(validateProbe(probe), []);
  assert.equal(probe.javacVersion, "17.0.19");
  assert.equal(probe.androidPlatformJarValid, true);
  assert.deepEqual(probe.executables, { adb: true, apksigner: true, zipalign: true, aapt2: true });
});

test("fails closed when JAVA_HOME has a runtime but no javac", async (t) => {
  const fixture = await createToolchainFixture(t);
  await rm(path.join(fixture.paths.jdk, "bin", "javac"));

  await assert.rejects(
    probeToolchain(fixture.env, { timeoutMs: 5_000 }),
    /javac/,
  );
});

test("rejects a nonempty android.jar that the JDK cannot list", async (t) => {
  const fixture = await createToolchainFixture(t);
  await writeExecutable(path.join(fixture.paths.jdk, "bin", "jar"), "process.exit(1);");

  const probe = await probeToolchain(fixture.env, { timeoutMs: 5_000 });

  assert.equal(probe.androidPlatformJarValid, false);
  assert.match(validateProbe(probe).join("\n"), /android-35\/android\.jar is missing or invalid/);
});

test("rejects an empty android.jar without trusting its filename", async (t) => {
  const fixture = await createToolchainFixture(t);
  await writeFile(fixture.paths.platformJar, "");

  const probe = await probeToolchain(fixture.env, { timeoutMs: 5_000 });

  assert.equal(probe.androidPlatformJarValid, false);
  assert.match(validateProbe(probe).join("\n"), /android-35\/android\.jar is missing or invalid/);
});

test("rejects an executable that cannot complete its safe version command", async (t) => {
  const fixture = await createToolchainFixture(t);
  await writeExecutable(fixture.paths.tools.adb, "process.exit(1);");

  const probe = await probeToolchain(fixture.env, { timeoutMs: 5_000 });

  assert.equal(probe.executables.adb, false);
  assert.match(validateProbe(probe).join("\n"), /adb is missing or unusable/);
});

test("times out a hung Android executable and fails closed", async (t) => {
  const fixture = await createToolchainFixture(t);
  await writeExecutable(fixture.paths.tools.aapt2, "setInterval(() => {}, 1_000);");

  const probe = await probeToolchain(fixture.env, { timeoutMs: 2_000 });

  assert.equal(probe.executables.aapt2, false);
  assert.match(validateProbe(probe).join("\n"), /aapt2 is missing or unusable/);
});

test("CLI succeeds with a complete fixture", async (t) => {
  const fixture = await createToolchainFixture(t);
  const result = spawnSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    env: fixture.env,
    encoding: "utf8",
    timeout: 10_000,
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /PASS: Godot 4\.7\.1/);
});

test("CLI exits nonzero for a mismatched pinned Godot build", async (t) => {
  const fixture = await createToolchainFixture(t);
  await writeExecutable(fixture.paths.godot, 'console.log("4.7.1.rc1.custom");');
  const result = spawnSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    env: fixture.env,
    encoding: "utf8",
    timeout: 10_000,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /BLOCKED: Godot must be 4\.7\.1\.stable\.official\.a13da4feb/);
});

test("CLI exits nonzero when required environment variables are absent", () => {
  const env = { ...process.env };
  delete env.JAVA_HOME;
  delete env.ANDROID_HOME;
  delete env.ANDROID_SDK_ROOT;
  const result = spawnSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    env,
    encoding: "utf8",
    timeout: 10_000,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /BLOCKED: ANDROID_SDK_ROOT or ANDROID_HOME must be set/);
});

test("CLI exits nonzero when JAVA_HOME is absent", async (t) => {
  const fixture = await createToolchainFixture(t);
  const env = { ...fixture.env };
  delete env.JAVA_HOME;
  const result = spawnSync(process.execPath, [scriptPath], {
    cwd: repoRoot,
    env,
    encoding: "utf8",
    timeout: 10_000,
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /BLOCKED: JAVA_HOME must be set/);
});
