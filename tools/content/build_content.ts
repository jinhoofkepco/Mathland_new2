import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ACTIVITY_IDS,
  canonicalJson,
  contentChecksum,
  validateContentManifest,
  validatePublishedActivity,
  type ActivityPackageDraftV1,
  type ActivityPackageV1,
  type ContentManifestV1,
  type SemanticVersion,
} from "../../packages/contracts/src/index.js";

import { readActivitySources, verifyAllSamples, type ContentSampleSummary } from "./verify_all_samples.js";
import { validateContentOnDisk } from "./validate_content.js";

const SEMANTIC_VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const GENERATED_ROOTS = ["content/packages", "content/manifests"] as const;
const ACTIVE_MANIFEST = "content/active-manifest.json";

export interface ContentBundleMetadata {
  contentVersion: string;
  manifestVersion: string;
  publishedAt: string;
}

export interface ContentBuildOptions extends ContentBundleMetadata {
  rootDir: string;
  check?: boolean;
}

export interface ContentBuildSummary extends ContentSampleSummary {
  checked: boolean;
}

export interface GeneratedContentBundle {
  files: ReadonlyMap<string, string>;
  manifest: ContentManifestV1;
  packagesByPath: ReadonlyMap<string, ActivityPackageV1>;
  summary: ContentSampleSummary;
}

export function readSourceDrafts(rootDir: string): ActivityPackageDraftV1[] {
  return readActivitySources(rootDir);
}

export function createContentBundle(
  unorderedSources: readonly ActivityPackageDraftV1[],
  metadata: ContentBundleMetadata,
): GeneratedContentBundle {
  assertMetadata(metadata);
  const summary = verifyAllSamples(unorderedSources);
  const byId = new Map(unorderedSources.map((source) => [source.activity_id, source] as const));
  const packagesByPath = new Map<string, ActivityPackageV1>();

  for (const activityId of ACTIVITY_IDS) {
    const source = byId.get(activityId);
    if (source === undefined) throw new Error(`Missing activity source ${activityId}`);
    if (source.content_version !== metadata.contentVersion) {
      throw new Error(
        `${activityId} content version ${source.content_version} does not match requested ${metadata.contentVersion}`,
      );
    }
    const checksum = contentChecksum(source);
    const published = { ...source, checksum } as ActivityPackageV1;
    const packageReport = validatePublishedActivity(published);
    if (!packageReport.valid) {
      throw reportError(`Generated package ${activityId} is invalid`, packageReport.issues);
    }
    packagesByPath.set(packagePath(activityId, metadata.contentVersion), published);
  }

  const manifest: ContentManifestV1 = {
    schema_version: 1,
    manifest_version: metadata.manifestVersion as SemanticVersion,
    published_at: metadata.publishedAt,
    activity_order: [...ACTIVITY_IDS],
    packages: ACTIVITY_IDS.map((activityId) => {
      const path = packagePath(activityId, metadata.contentVersion);
      const published = packagesByPath.get(path);
      if (published === undefined) throw new Error(`Internal build error: missing ${path}`);
      return {
        activity_id: activityId,
        content_version: metadata.contentVersion as SemanticVersion,
        path: path as ContentManifestV1["packages"][number]["path"],
        checksum: published.checksum,
      };
    }),
  };
  const manifestReport = validateContentManifest(manifest, packagesByPath);
  if (!manifestReport.valid) {
    throw reportError("Generated content manifest is invalid", manifestReport.issues);
  }

  const files = new Map<string, string>();
  for (const [path, published] of packagesByPath) files.set(path, `${canonicalJson(published)}\n`);
  const manifestSource = `${canonicalJson(manifest)}\n`;
  files.set(`content/manifests/${metadata.manifestVersion}.json`, manifestSource);
  files.set(ACTIVE_MANIFEST, manifestSource);
  return {
    files: new Map([...files].sort(([left], [right]) => left.localeCompare(right))),
    manifest,
    packagesByPath,
    summary,
  };
}

export async function buildContent(options: ContentBuildOptions): Promise<ContentBuildSummary> {
  const rootDir = resolve(options.rootDir);
  const bundle = createContentBundle(readSourceDrafts(rootDir), options);
  if (options.check === true) {
    assertGeneratedFilesMatch(rootDir, bundle.files);
    return { ...bundle.summary, checked: true };
  }

  const stagingRoot = mkdtempSync(join(rootDir, ".content-build-staging-"));
  try {
    writeBundle(stagingRoot, bundle.files);
    const stagedSummary = validateContentOnDisk({ rootDir: stagingRoot });
    if (canonicalJson(stagedSummary) !== canonicalJson(bundle.summary)) {
      throw new Error("Staged bundle summary differs from the verified source summary");
    }
    replaceGeneratedOutputs(rootDir, stagingRoot);
  } finally {
    rmSync(stagingRoot, { recursive: true, force: true });
  }
  return { ...bundle.summary, checked: false };
}

function assertMetadata(metadata: ContentBundleMetadata): void {
  if (!SEMANTIC_VERSION.test(metadata.contentVersion)) {
    throw new Error(`Invalid content version: ${metadata.contentVersion}`);
  }
  if (!SEMANTIC_VERSION.test(metadata.manifestVersion)) {
    throw new Error(`Invalid manifest version: ${metadata.manifestVersion}`);
  }
  const instant = new Date(metadata.publishedAt);
  if (!Number.isFinite(instant.getTime()) || instant.toISOString() !== metadata.publishedAt) {
    throw new Error(`published-at must be a canonical UTC timestamp: ${metadata.publishedAt}`);
  }
}

function packagePath(activityId: (typeof ACTIVITY_IDS)[number], contentVersion: string): string {
  return `content/packages/${activityId}/${contentVersion}.json`;
}

function writeBundle(rootDir: string, files: ReadonlyMap<string, string>): void {
  for (const [relativePath, source] of files) {
    const target = safeResolve(rootDir, relativePath);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, source, { encoding: "utf8", flag: "wx" });
  }
}

function assertGeneratedFilesMatch(rootDir: string, expected: ReadonlyMap<string, string>): void {
  const actualPaths = collectGeneratedFiles(rootDir);
  const expectedPaths = [...expected.keys()].sort();
  if (canonicalJson(actualPaths) !== canonicalJson(expectedPaths)) {
    throw new Error(
      `Content bundle drift: expected files ${expectedPaths.join(", ")}; received ${actualPaths.join(", ")}`,
    );
  }
  for (const [relativePath, source] of expected) {
    const target = safeResolve(rootDir, relativePath);
    if (readFileSync(target, "utf8") !== source) {
      throw new Error(`Content bundle drift: ${relativePath} is not reproducible`);
    }
  }
}

function collectGeneratedFiles(rootDir: string): string[] {
  const result: string[] = [];
  const visit = (relativePath: string): void => {
    const absolutePath = safeResolve(rootDir, relativePath);
    if (!existsSync(absolutePath)) return;
    for (const entry of readdirSync(absolutePath, { withFileTypes: true })) {
      const child = `${relativePath}/${entry.name}`;
      if (entry.isDirectory()) visit(child);
      else if (entry.isFile()) result.push(child);
      else result.push(`${child}#unsupported`);
    }
  };
  for (const generatedRoot of GENERATED_ROOTS) visit(generatedRoot);
  if (existsSync(safeResolve(rootDir, ACTIVE_MANIFEST))) result.push(ACTIVE_MANIFEST);
  return result.sort();
}

function replaceGeneratedOutputs(rootDir: string, stagingRoot: string): void {
  const backupRoot = mkdtempSync(join(rootDir, ".content-build-backup-"));
  const targets = [...GENERATED_ROOTS, ACTIVE_MANIFEST];
  const backedUp: string[] = [];
  const installed: string[] = [];
  try {
    for (const relativePath of targets) {
      const current = safeResolve(rootDir, relativePath);
      if (!existsSync(current)) continue;
      const backup = safeResolve(backupRoot, relativePath);
      mkdirSync(dirname(backup), { recursive: true });
      renameSync(current, backup);
      backedUp.push(relativePath);
    }
    for (const relativePath of targets) {
      const staged = safeResolve(stagingRoot, relativePath);
      if (!existsSync(staged)) throw new Error(`Staged output is missing ${relativePath}`);
      const target = safeResolve(rootDir, relativePath);
      mkdirSync(dirname(target), { recursive: true });
      renameSync(staged, target);
      installed.push(relativePath);
    }
  } catch (error) {
    for (const relativePath of installed.reverse()) {
      rmSync(safeResolve(rootDir, relativePath), { recursive: true, force: true });
    }
    for (const relativePath of backedUp.reverse()) {
      const backup = safeResolve(backupRoot, relativePath);
      const target = safeResolve(rootDir, relativePath);
      mkdirSync(dirname(target), { recursive: true });
      renameSync(backup, target);
    }
    throw error;
  } finally {
    rmSync(backupRoot, { recursive: true, force: true });
  }
}

function safeResolve(rootDir: string, relativePath: string): string {
  const root = resolve(rootDir);
  const target = resolve(root, relativePath);
  if (target !== root && !target.startsWith(`${root}${sep}`)) {
    throw new Error(`Path escapes content root: ${relativePath}`);
  }
  return target;
}

function reportError(
  prefix: string,
  issues: readonly { code: string; path: readonly (string | number)[]; message: string }[],
): Error {
  return new Error(
    `${prefix}: ${issues.map((issue) => `${issue.code}@${issue.path.join(".")}: ${issue.message}`).join("; ")}`,
  );
}

function parseCli(argv: readonly string[]): ContentBuildOptions {
  const values = new Map<string, string>();
  let check = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]!;
    if (argument === "--check") {
      check = true;
      continue;
    }
    if (!["--content-version", "--manifest-version", "--published-at", "--root"].includes(argument)) {
      throw new Error(`Unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) throw new Error(`Missing value for ${argument}`);
    values.set(argument, value);
    index += 1;
  }
  const contentVersion = values.get("--content-version");
  const manifestVersion = values.get("--manifest-version");
  const publishedAt = values.get("--published-at");
  if (contentVersion === undefined || manifestVersion === undefined || publishedAt === undefined) {
    throw new Error("--content-version, --manifest-version, and --published-at are required");
  }
  return {
    rootDir: resolve(values.get("--root") ?? process.cwd()),
    contentVersion,
    manifestVersion,
    publishedAt,
    check,
  };
}

function isDirectInvocation(): boolean {
  return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isDirectInvocation()) {
  try {
    const result = await buildContent(parseCli(process.argv.slice(2)));
    process.stdout.write(
      `${result.checked ? "Checked" : "Built"} ${result.activities} activities, ${result.bands} bands, ${result.samples} samples\n`,
    );
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
