import { access, readdir } from "node:fs/promises";
import { constants } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REQUIRED_GODOT_PREFIX = "4.7.1.";
const REQUIRED_JAVA_MAJOR = "17";
const REQUIRED_PLATFORM = "android-35";
const REQUIRED_BUILD_TOOLS = "35.0.1";
const REQUIRED_EXECUTABLES = ["adb", "apksigner", "zipalign", "aapt2"];

export function validateProbe(probe) {
  const value = probe && typeof probe === "object" ? probe : {};
  const godotVersion = typeof value.godotVersion === "string" ? value.godotVersion : "unknown";
  const javaVersion = typeof value.javaVersion === "string" ? value.javaVersion : "unknown";
  const platforms = Array.isArray(value.platforms) ? value.platforms : [];
  const buildTools = Array.isArray(value.buildTools) ? value.buildTools : [];
  const executables = value.executables && typeof value.executables === "object" ? value.executables : {};
  const findings = [];

  if (!godotVersion.startsWith(REQUIRED_GODOT_PREFIX)) {
    findings.push(`Godot must be 4.7.1; found ${godotVersion}`);
  }
  if (javaVersion.split(".")[0] !== REQUIRED_JAVA_MAJOR) {
    findings.push(`Java major version must be 17; found ${javaVersion}`);
  }
  if (!platforms.includes(REQUIRED_PLATFORM)) {
    findings.push(`Android platform ${REQUIRED_PLATFORM} is missing`);
  }
  if (!buildTools.includes(REQUIRED_BUILD_TOOLS)) {
    findings.push(`Android build-tools ${REQUIRED_BUILD_TOOLS} is missing`);
  }
  for (const name of REQUIRED_EXECUTABLES) {
    if (executables[name] !== true) {
      findings.push(`Android executable ${name} is missing`);
    }
  }
  return findings;
}

function capture(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error) {
    throw new Error(`Unable to run ${command}: ${result.error.code || "spawn_failed"}`);
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited ${result.status}`);
  }
  return `${result.stdout || ""}${result.stderr || ""}`.trim();
}

async function executableExists(file) {
  try {
    await access(file, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export async function probeToolchain(env = process.env) {
  const sdk = env.ANDROID_SDK_ROOT || env.ANDROID_HOME;
  if (!sdk) {
    throw new Error("ANDROID_SDK_ROOT or ANDROID_HOME must be set");
  }
  if (!env.JAVA_HOME) {
    throw new Error("JAVA_HOME must be set");
  }
  const godot = env.GODOT_BIN || "/opt/homebrew/bin/godot";
  const java = path.join(env.JAVA_HOME, "bin", "java");
  const javaText = capture(java, ["-version"]);
  const javaVersion = /version "([^"]+)"/.exec(javaText)?.[1] || "unknown";
  const toolDir = path.join(sdk, "build-tools", REQUIRED_BUILD_TOOLS);
  return {
    godotVersion: capture(godot, ["--version"]),
    javaVersion,
    platforms: await readdir(path.join(sdk, "platforms")),
    buildTools: await readdir(path.join(sdk, "build-tools")),
    executables: {
      adb: await executableExists(path.join(sdk, "platform-tools", "adb")),
      apksigner: await executableExists(path.join(toolDir, "apksigner")),
      zipalign: await executableExists(path.join(toolDir, "zipalign")),
      aapt2: await executableExists(path.join(toolDir, "aapt2")),
    },
  };
}

async function main() {
  try {
    const findings = validateProbe(await probeToolchain());
    if (findings.length > 0) {
      for (const finding of findings) {
        console.error(`BLOCKED: ${finding}`);
      }
      process.exitCode = 1;
      return;
    }
    console.log("PASS: Godot 4.7.1 / JDK 17 / Android 35 / build-tools 35.0.1");
  } catch (error) {
    console.error(`BLOCKED: ${error instanceof Error ? error.message : "toolchain probe failed"}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
