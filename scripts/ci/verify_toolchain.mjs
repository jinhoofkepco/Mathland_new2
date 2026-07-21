import { readdir, stat } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REQUIRED_GODOT_VERSION = "4.7.1.stable.official.a13da4feb";
const REQUIRED_JAVA_MAJOR = "17";
const REQUIRED_PLATFORM = "android-35";
const REQUIRED_BUILD_TOOLS = "35.0.1";
const REQUIRED_GODOT_BUILD_TOOLS = "36.1.0";
const REQUIRED_EXECUTABLES = ["adb", "apksigner", "zipalign", "aapt2"];
const ANDROID_JAR_SENTINEL = "android/app/Activity.class";
const DEFAULT_COMMAND_TIMEOUT_MS = 5_000;

export function validateProbe(probe) {
  const value = probe && typeof probe === "object" ? probe : {};
  const godotVersion = typeof value.godotVersion === "string" ? value.godotVersion : "unknown";
  const javaVersion = typeof value.javaVersion === "string" ? value.javaVersion : "unknown";
  const javacVersion = typeof value.javacVersion === "string" ? value.javacVersion : "unknown";
  const platforms = Array.isArray(value.platforms) ? value.platforms : [];
  const buildTools = Array.isArray(value.buildTools) ? value.buildTools : [];
  const executables = value.executables && typeof value.executables === "object" ? value.executables : {};
  const findings = [];

  if (godotVersion !== REQUIRED_GODOT_VERSION) {
    findings.push(`Godot must be ${REQUIRED_GODOT_VERSION}; found ${godotVersion}`);
  }
  if (javaVersion.split(".")[0] !== REQUIRED_JAVA_MAJOR) {
    findings.push(`Java major version must be 17; found ${javaVersion}`);
  }
  if (javacVersion.split(".")[0] !== REQUIRED_JAVA_MAJOR) {
    findings.push(`Javac major version must be 17; found ${javacVersion}`);
  }
  if (!platforms.includes(REQUIRED_PLATFORM)) {
    findings.push(`Android platform ${REQUIRED_PLATFORM} is missing`);
  }
  if (value.androidPlatformJarValid !== true) {
    findings.push(`Android platform ${REQUIRED_PLATFORM}/android.jar is missing or invalid`);
  }
  if (!buildTools.includes(REQUIRED_BUILD_TOOLS)) {
    findings.push(`Android build-tools ${REQUIRED_BUILD_TOOLS} is missing`);
  }
  if (!buildTools.includes(REQUIRED_GODOT_BUILD_TOOLS)) {
    findings.push(`Godot Android build-tools ${REQUIRED_GODOT_BUILD_TOOLS} is missing`);
  }
  for (const name of REQUIRED_EXECUTABLES) {
    if (executables[name] !== true) {
      findings.push(`Android executable ${name} is missing or unusable`);
    }
  }
  return findings;
}

function runCommand(command, args, timeoutMs, ignoreOutput = false) {
  return spawnSync(command, args, {
    encoding: ignoreOutput ? undefined : "utf8",
    maxBuffer: 256 * 1024,
    shell: false,
    stdio: ignoreOutput ? "ignore" : "pipe",
    timeout: timeoutMs,
    windowsHide: true,
  });
}

function capture(command, args, timeoutMs) {
  const result = runCommand(command, args, timeoutMs);
  if (result.error) {
    const reason = result.error.code === "ETIMEDOUT"
      ? `timed out after ${timeoutMs}ms`
      : result.error.code || "spawn_failed";
    throw new Error(`Unable to run ${command}: ${reason}`);
  }
  if (result.status !== 0) {
    throw new Error(`${command} exited ${result.status}`);
  }
  return `${result.stdout || ""}\n${result.stderr || ""}`.trim();
}

function commandIsUsable(command, args, options) {
  const result = runCommand(command, args, options.timeoutMs, options.ignoreOutput === true);
  if (result.error || !options.acceptedStatuses.includes(result.status)) {
    return false;
  }
  if (!options.outputPattern) {
    return true;
  }
  const output = `${result.stdout || ""}\n${result.stderr || ""}`;
  return options.outputPattern.test(output);
}

function isExactSingleLine(output, expected) {
  const withoutTerminalLineEnding = output.endsWith("\r\n")
    ? output.slice(0, -2)
    : output.endsWith("\n")
      ? output.slice(0, -1)
      : output;
  return withoutTerminalLineEnding === expected;
}

async function isValidAndroidJar(jarCommand, androidJar, timeoutMs) {
  try {
    const info = await stat(androidJar);
    if (!info.isFile() || info.size === 0) {
      return false;
    }
  } catch {
    return false;
  }
  try {
    const result = runCommand(jarCommand, ["tf", androidJar, ANDROID_JAR_SENTINEL], timeoutMs);
    return (
      !result.error
      && result.status === 0
      && (result.stderr || "") === ""
      && isExactSingleLine(result.stdout || "", ANDROID_JAR_SENTINEL)
    );
  } catch {
    return false;
  }
}

export async function probeToolchain(env = process.env, options = {}) {
  const sdk = env.ANDROID_SDK_ROOT || env.ANDROID_HOME;
  if (!sdk) {
    throw new Error("ANDROID_SDK_ROOT or ANDROID_HOME must be set");
  }
  if (!env.JAVA_HOME) {
    throw new Error("JAVA_HOME must be set");
  }
  const requestedTimeout = Number.isInteger(options.timeoutMs) && options.timeoutMs > 0
    ? options.timeoutMs
    : DEFAULT_COMMAND_TIMEOUT_MS;
  const timeoutMs = Math.min(requestedTimeout, DEFAULT_COMMAND_TIMEOUT_MS);
  const godot = env.GODOT_BIN || "/opt/homebrew/bin/godot";
  const java = path.join(env.JAVA_HOME, "bin", "java");
  const javac = path.join(env.JAVA_HOME, "bin", "javac");
  const jar = path.join(env.JAVA_HOME, "bin", "jar");
  const javaText = capture(java, ["-version"], timeoutMs);
  const javacText = capture(javac, ["-version"], timeoutMs);
  const javaVersion = /version "([^"]+)"/.exec(javaText)?.[1] || "unknown";
  const javacVersion = /javac\s+([^\s]+)/.exec(javacText)?.[1] || "unknown";
  const toolDir = path.join(sdk, "build-tools", REQUIRED_BUILD_TOOLS);
  const androidJar = path.join(sdk, "platforms", REQUIRED_PLATFORM, "android.jar");
  return {
    godotVersion: capture(godot, ["--version"], timeoutMs),
    javaVersion,
    javacVersion,
    platforms: await readdir(path.join(sdk, "platforms")),
    androidPlatformJarValid: await isValidAndroidJar(jar, androidJar, timeoutMs),
    buildTools: await readdir(path.join(sdk, "build-tools")),
    executables: {
      adb: commandIsUsable(path.join(sdk, "platform-tools", "adb"), ["version"], {
        acceptedStatuses: [0],
        outputPattern: /Android Debug Bridge version/i,
        timeoutMs,
      }),
      apksigner: commandIsUsable(path.join(toolDir, "apksigner"), ["version"], {
        acceptedStatuses: [0],
        outputPattern: /^\s*\d+(?:\.\d+)+(?:\s|$)/m,
        timeoutMs,
      }),
      zipalign: commandIsUsable(path.join(toolDir, "zipalign"), [], {
        acceptedStatuses: [2],
        outputPattern: /(?:Zip alignment utility|Usage:\s*zipalign)/i,
        timeoutMs,
      }),
      aapt2: commandIsUsable(path.join(toolDir, "aapt2"), ["version"], {
        acceptedStatuses: [0],
        outputPattern: /Android Asset Packaging Tool/i,
        timeoutMs,
      }),
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
    console.log(
      `PASS: Godot ${REQUIRED_GODOT_VERSION} / JDK 17 / Android 35 / build-tools 35.0.1 + 36.1.0`,
    );
  } catch (error) {
    console.error(`BLOCKED: ${error instanceof Error ? error.message : "toolchain probe failed"}`);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
