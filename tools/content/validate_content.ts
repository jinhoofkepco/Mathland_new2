import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
} from "node:fs";
import { resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ContentManifestV1Schema,
  canonicalJson,
  parseJsonStrict,
  validateContentManifest,
  type ActivityPackageDraftV1,
  type ContentManifestV1,
} from "../../packages/contracts/src/index.js";

import { verifyAllSamples, type ContentSampleSummary } from "./verify_all_samples.js";

export interface ValidateContentOptions {
  rootDir: string;
  manifestPath?: string;
}

export function validateContentOnDisk(options: ValidateContentOptions): ContentSampleSummary {
  const rootDir = resolve(options.rootDir);
  const manifestRelativePath = options.manifestPath ?? "content/active-manifest.json";
  const manifestPath = safeRegularFile(rootDir, manifestRelativePath);
  const manifestSource = readFileSync(manifestPath, "utf8");
  const manifestValue = parseJsonStrict(manifestSource);
  const manifestParse = ContentManifestV1Schema.safeParse(manifestValue);
  if (!manifestParse.success) {
    throw new Error(
      `Invalid content manifest: ${manifestParse.error.issues.map((issue) => `${issue.code}@${issue.path.join(".")}: ${issue.message}`).join("; ")}`,
    );
  }
  const manifest = manifestParse.data as ContentManifestV1;
  const packagesByPath = new Map<string, unknown>();
  for (const entry of manifest.packages) {
    const packageFile = safeRegularFile(rootDir, entry.path);
    packagesByPath.set(entry.path, parseJsonStrict(readFileSync(packageFile, "utf8")));
  }
  const report = validateContentManifest(manifest, packagesByPath);
  if (!report.valid) {
    throw new Error(
      `Invalid content bundle: ${report.issues.map((issue) => `${issue.code}@${issue.path.join(".")}: ${issue.message}`).join("; ")}`,
    );
  }

  const immutablePath = safeRegularFile(
    rootDir,
    `content/manifests/${manifest.manifest_version}.json`,
  );
  const immutableManifest = parseJsonStrict(readFileSync(immutablePath, "utf8"));
  if (canonicalJson(immutableManifest) !== canonicalJson(manifest)) {
    throw new Error("Active manifest does not match its immutable manifest");
  }

  return verifyAllSamples([...packagesByPath.values()] as ActivityPackageDraftV1[]);
}

function safeRegularFile(rootDir: string, relativePath: string): string {
  const target = resolve(rootDir, relativePath);
  if (target === rootDir || !target.startsWith(`${rootDir}${sep}`)) {
    throw new Error(`Manifest path escapes repository root: ${relativePath}`);
  }
  if (!existsSync(target)) throw new Error(`Content file is missing: ${relativePath}`);
  if (!lstatSync(target).isFile()) throw new Error(`Content path is not a regular file: ${relativePath}`);
  const realRoot = realpathSync(rootDir);
  const realTarget = realpathSync(target);
  if (!realTarget.startsWith(`${realRoot}${sep}`)) {
    throw new Error(`Content file resolves outside repository root: ${relativePath}`);
  }
  return realTarget;
}

function parseCli(argv: readonly string[]): ValidateContentOptions {
  let rootDir = process.cwd();
  let manifestPath = "content/active-manifest.json";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]!;
    if (!["--root", "--manifest"].includes(argument)) throw new Error(`Unknown argument: ${argument}`);
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) throw new Error(`Missing value for ${argument}`);
    if (argument === "--root") rootDir = value;
    else manifestPath = value;
    index += 1;
  }
  return { rootDir: resolve(rootDir), manifestPath };
}

function isDirectInvocation(): boolean {
  return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isDirectInvocation()) {
  try {
    const summary = validateContentOnDisk(parseCli(process.argv.slice(2)));
    process.stdout.write(
      `Validated ${summary.activities} activities, ${summary.bands} bands, ${summary.samples} samples; manifest checksum set valid\n`,
    );
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
