import { createHash } from "node:crypto";
import { inflateSync } from "node:zlib";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  AssetManifestSchema,
  MATHLAND_PALETTE,
  type AssetIssue,
  type AssetManifest,
  type AssetRecord,
  type AssetReport,
} from "./asset_schema.js";
import { validateSvgText } from "./validate_svg.js";

const RELEASE_EXTENSIONS = new Set([".svg", ".png", ".webp", ".ogg", ".wav", ".mp3"]);
const CONSUMER_EXTENSIONS = new Set([".json", ".tscn", ".tres", ".gd", ".cfg"]);
const MAX_RELEASE_RASTER_BYTES = 6 * 1024 * 1024;
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export interface AssetWorkspaceOptions {
  readonly root?: string;
  readonly rootDir?: string;
  readonly manifestPath: string;
  readonly licensesPath: string;
}

export interface PngInspection {
  readonly width: number;
  readonly height: number;
  readonly hasAlpha: boolean;
  readonly colorSpace: "sRGB" | "unspecified";
  readonly cornerAlphas: readonly [number, number, number, number];
  readonly isFullyOpaque: boolean;
}

export function validateAssetManifest(value: unknown): AssetReport {
  const issues: AssetIssue[] = [];
  const raw = isRecord(value) ? value : {};
  const assets = Array.isArray(raw.assets) ? raw.assets : [];
  const parsed = AssetManifestSchema.safeParse(value);
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      const field = issue.path.at(-1);
      const code =
        field === "origin"
          ? "PROVENANCE_REQUIRED"
          : field === "license"
            ? "LICENSE_REQUIRED"
            : field === "redistribution"
              ? "RIGHTS_REQUIRED"
              : "ASSET_SCHEMA_INVALID";
      const issuePath = issue.path.map((segment) =>
        typeof segment === "symbol" ? segment.description ?? "symbol" : segment,
      );
      pushUnique(issues, { code, path: issuePath, message: issue.message });
    }
  }

  const ids = new Set<string>();
  const paths = new Set<string>();
  const rawByPath = new Map<string, Record<string, unknown>>();
  for (const candidate of assets) {
    if (isRecord(candidate) && typeof candidate.path === "string") {
      rawByPath.set(candidate.path, candidate);
    }
  }
  assets.forEach((candidate, index) => {
    if (!isRecord(candidate)) {
      return;
    }
    const id = typeof candidate.id === "string" ? candidate.id : undefined;
    const assetPath = typeof candidate.path === "string" ? candidate.path : undefined;
    if (id !== undefined && ids.has(id)) {
      pushUnique(issues, {
        code: "DUPLICATE_ID",
        path: ["assets", index, "id"],
        message: `Duplicate asset ID ${id}`,
      });
    }
    if (id !== undefined) ids.add(id);
    if (assetPath !== undefined && paths.has(assetPath)) {
      pushUnique(issues, {
        code: "DUPLICATE_PATH",
        path: ["assets", index, "path"],
        message: `Duplicate asset path ${assetPath}`,
      });
    }
    if (assetPath !== undefined) paths.add(assetPath);
    for (const field of ["path", "source_path", "master_path", "prompt_path", "generation_script", "input_path"] as const) {
      const candidatePath = candidate[field];
      if (typeof candidatePath === "string" && !isSafeRepositoryPath(candidatePath)) {
        pushUnique(issues, {
          code: "UNSAFE_PATH",
          path: ["assets", index, field],
          message: `${field} must be a normalized repository-relative path`,
        });
      }
    }
    if (candidate.release === true && candidate.redistribution !== "confirmed") {
      pushUnique(issues, {
        code: "RELEASE_RIGHTS_UNCONFIRMED",
        path: ["assets", index, "redistribution"],
        message: "Release assets require confirmed redistribution rights",
      });
    }
    if (
      candidate.kind === "png" &&
      candidate.release === true &&
      candidate.origin === "generated-derived"
    ) {
      const masterPath = candidate.master_path;
      const master = typeof masterPath === "string" ? rawByPath.get(masterPath) : undefined;
      if (
        typeof masterPath !== "string" ||
        masterPath === assetPath ||
        master === undefined ||
        master.release === true
      ) {
        pushUnique(issues, {
          code: "GENERATED_MASTER_INVALID",
          path: ["assets", index, "master_path"],
          message: "Generated release masters must be genuine non-release asset records",
        });
      }
      const transformation = candidate.transformation;
      if (
        isRecord(transformation) &&
        (transformation.output_width !== candidate.width ||
          transformation.output_height !== candidate.height)
      ) {
        pushUnique(issues, {
          code: "RASTER_TRANSFORMATION_INVALID",
          path: ["assets", index, "transformation"],
          message: "Transformation output dimensions must match the release dimensions",
        });
      }
    }
  });

  if (
    Array.isArray(raw.palette) &&
    JSON.stringify(raw.palette) !== JSON.stringify(MATHLAND_PALETTE)
  ) {
    pushUnique(issues, {
      code: "PALETTE_MISMATCH",
      path: ["palette"],
      message: "Manifest palette must exactly match the canonical MathLand palette",
    });
  }
  return report(issues);
}

export async function validateAssetWorkspace(options: AssetWorkspaceOptions): Promise<AssetReport> {
  const root = path.resolve(options.root ?? options.rootDir ?? process.cwd());
  const issues: AssetIssue[] = [];
  let value: unknown;
  try {
    value = JSON.parse(await readFile(options.manifestPath, "utf8")) as unknown;
  } catch (error) {
    return report([
      {
        code: "MANIFEST_READ_FAILED",
        path: [],
        message: error instanceof Error ? error.message : "Unable to read asset manifest",
      },
    ]);
  }
  issues.push(...validateAssetManifest(value).issues);
  const parsed = AssetManifestSchema.safeParse(value);
  if (!parsed.success) {
    return report(issues);
  }
  const manifest = parsed.data as AssetManifest;

  let licenses = "";
  try {
    licenses = await readFile(options.licensesPath, "utf8");
  } catch (error) {
    pushUnique(issues, {
      code: "LICENSE_LEDGER_READ_FAILED",
      path: [],
      message: error instanceof Error ? error.message : "Unable to read license ledger",
    });
  }

  const releasePaths = new Set(manifest.assets.filter((asset) => asset.release).map((asset) => asset.path));
  const diskReleasePaths = new Set(await findReleaseFiles(root));
  for (const releasePath of diskReleasePaths) {
    if (!releasePaths.has(releasePath)) {
      pushUnique(issues, {
        code: "UNLISTED_RELEASE_FILE",
        path: [releasePath],
        message: `Release file is absent from the asset manifest: ${releasePath}`,
      });
    }
  }
  for (const releasePath of releasePaths) {
    if (!diskReleasePaths.has(releasePath)) {
      pushUnique(issues, {
        code: "MISSING_ASSET_FILE",
        path: [releasePath],
        message: `Manifest release file does not exist: ${releasePath}`,
      });
    }
  }

  const byPath = new Map(manifest.assets.map((asset) => [asset.path, asset]));
  for (const [index, asset] of manifest.assets.entries()) {
    const absolutePath = resolveSafe(root, asset.path);
    if (absolutePath === undefined || !(await isFile(absolutePath))) {
      pushUnique(issues, {
        code: "MISSING_ASSET_FILE",
        path: ["assets", index, "path"],
        message: `Asset file does not exist: ${asset.path}`,
      });
      continue;
    }
    const bytes = await readFile(absolutePath);
    const actualHash = createHash("sha256").update(bytes).digest("hex");
    if (actualHash !== asset.sha256) {
      pushUnique(issues, {
        code: "HASH_MISMATCH",
        path: ["assets", index, "sha256"],
        message: `SHA-256 mismatch for ${asset.path}`,
      });
    }
    if (!licenses.includes(`\`${asset.id}\``)) {
      pushUnique(issues, {
        code: "LICENSE_LEDGER_MISSING",
        path: ["assets", index, "id"],
        message: `License ledger has no record for ${asset.id}`,
      });
    }
    for (const [field, linkedPath] of linkedPaths(asset)) {
      const linkedAbsolute = resolveSafe(root, linkedPath);
      if (linkedAbsolute === undefined || !(await isFile(linkedAbsolute))) {
        pushUnique(issues, {
          code: "MISSING_PROVENANCE_FILE",
          path: ["assets", index, field],
          message: `Provenance file does not exist: ${linkedPath}`,
        });
      }
    }
    if (asset.prompt_path && asset.prompt_sha256) {
      const promptAbsolute = resolveSafe(root, asset.prompt_path);
      if (promptAbsolute && (await isFile(promptAbsolute))) {
        const promptHash = createHash("sha256").update(await readFile(promptAbsolute)).digest("hex");
        if (promptHash !== asset.prompt_sha256) {
          pushUnique(issues, {
            code: "PROMPT_HASH_MISMATCH",
            path: ["assets", index, "prompt_sha256"],
            message: `Saved prompt SHA-256 mismatch for ${asset.id}`,
          });
        }
      }
    }
    if (asset.release && asset.redistribution !== "confirmed") {
      pushUnique(issues, {
        code: "RELEASE_RIGHTS_UNCONFIRMED",
        path: ["assets", index, "redistribution"],
        message: `Release rights are not confirmed for ${asset.id}`,
      });
    }
    if (asset.release && Object.values(asset.review).some((flag) => flag !== true)) {
      pushUnique(issues, {
        code: "RELEASE_REVIEW_INCOMPLETE",
        path: ["assets", index, "review"],
        message: `Every release review flag must be true for ${asset.id}`,
      });
    }
    if (asset.release && asset.origin === "generated-derived") {
      const source = byPath.get(asset.source_path);
      const master = asset.master_path ? byPath.get(asset.master_path) : undefined;
      if (
        source === undefined ||
        source.release ||
        source.prompt_path !== asset.prompt_path ||
        source.prompt_sha256 !== asset.prompt_sha256 ||
        !asset.prompt_path
      ) {
        pushUnique(issues, {
          code: "GENERATED_LINKAGE_INVALID",
          path: ["assets", index],
          message: `Generated release ${asset.id} must link one non-release source and its exact prompt`,
        });
      }
      if (
        !asset.master_path ||
        asset.master_path === asset.path ||
        master === undefined ||
        master.release
      ) {
        pushUnique(issues, {
          code: "GENERATED_MASTER_INVALID",
          path: ["assets", index, "master_path"],
          message: `Generated release ${asset.id} must link a genuine non-release master`,
        });
      }
      if (
        asset.kind === "png" &&
        asset.transformation &&
        source &&
        (asset.transformation.source_width !== source.width ||
          asset.transformation.source_height !== source.height ||
          asset.transformation.output_width !== asset.width ||
          asset.transformation.output_height !== asset.height)
      ) {
        pushUnique(issues, {
          code: "RASTER_TRANSFORMATION_INVALID",
          path: ["assets", index, "transformation"],
          message: `Declared raster transformation dimensions do not match ${asset.source_path} and ${asset.path}`,
        });
      }
    }
    if (asset.kind === "svg") {
      const svg = bytes.toString("utf8");
      const svgIssues = validateSvgText(svg, {
        expectedViewBox: asset.view_box ?? "",
        palette: manifest.palette,
      });
      for (const svgIssue of svgIssues) {
        pushUnique(issues, {
          ...svgIssue,
          path: ["assets", index, ...svgIssue.path],
          message: `${asset.path}: ${svgIssue.message}`,
        });
      }
    }
    if (asset.kind === "png") {
      validatePngAsset(asset, bytes, index, issues);
    }
  }

  for (const reference of await findCandidateReferences(root)) {
    pushUnique(issues, {
      code: "RELEASE_REFERENCES_CANDIDATE",
      path: [reference],
      message: `Runtime file directly references a source candidate: ${reference}`,
    });
  }
  return report(issues);
}

export function inspectPng(bytes: Uint8Array): PngInspection {
  const input = Buffer.from(bytes);
  if (input.byteLength < 33 || !input.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new TypeError("Invalid PNG signature");
  }
  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = -1;
  let interlace = -1;
  let colorSpace: "sRGB" | "unspecified" = "unspecified";
  const idat: Buffer[] = [];
  while (offset + 12 <= input.byteLength) {
    const length = input.readUInt32BE(offset);
    const type = input.toString("ascii", offset + 4, offset + 8);
    const start = offset + 8;
    const end = start + length;
    if (end + 4 > input.byteLength) throw new TypeError("Truncated PNG chunk");
    const data = input.subarray(start, end);
    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8] ?? 0;
      colorType = data[9] ?? -1;
      interlace = data[12] ?? -1;
    } else if (type === "sRGB") {
      colorSpace = "sRGB";
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    offset = end + 4;
  }
  if (width < 1 || height < 1 || bitDepth !== 8 || ![2, 6].includes(colorType) || interlace !== 0) {
    throw new TypeError("PNG must be non-interlaced 8-bit RGB or RGBA");
  }
  const hasAlpha = colorType === 6;
  if (!hasAlpha) {
    return {
      width,
      height,
      hasAlpha,
      colorSpace,
      cornerAlphas: [255, 255, 255, 255],
      isFullyOpaque: true,
    };
  }
  const channels = 4;
  const rowBytes = width * channels;
  const inflated = inflateSync(Buffer.concat(idat));
  if (inflated.byteLength !== height * (rowBytes + 1)) {
    throw new TypeError("Unexpected PNG pixel payload length");
  }
  let previous: Uint8Array = new Uint8Array(rowBytes);
  const cornerAlphas: [number, number, number, number] = [255, 255, 255, 255];
  let isFullyOpaque = true;
  for (let y = 0; y < height; y += 1) {
    const sourceOffset = y * (rowBytes + 1);
    const filter = inflated[sourceOffset] ?? -1;
    const source = inflated.subarray(sourceOffset + 1, sourceOffset + 1 + rowBytes);
    const row = unfilterRow(source, previous, channels, filter);
    for (let x = 0; x < width; x += 1) {
      const alpha = row[x * channels + 3] ?? 255;
      if (alpha !== 255) isFullyOpaque = false;
    }
    if (y === 0) {
      cornerAlphas[0] = row[3] ?? 255;
      cornerAlphas[1] = row[(width - 1) * channels + 3] ?? 255;
    }
    if (y === height - 1) {
      cornerAlphas[2] = row[3] ?? 255;
      cornerAlphas[3] = row[(width - 1) * channels + 3] ?? 255;
    }
    previous = row;
  }
  return { width, height, hasAlpha, colorSpace, cornerAlphas, isFullyOpaque };
}

function validatePngAsset(
  asset: AssetRecord,
  bytes: Buffer,
  index: number,
  issues: AssetIssue[],
): void {
  let png: PngInspection;
  try {
    png = inspectPng(bytes);
  } catch (error) {
    pushUnique(issues, {
      code: "PNG_INVALID",
      path: ["assets", index, "path"],
      message: `${asset.path}: ${error instanceof Error ? error.message : "Invalid PNG"}`,
    });
    return;
  }
  if (png.width !== asset.width || png.height !== asset.height) {
    pushUnique(issues, {
      code: "RASTER_DIMENSION_MISMATCH",
      path: ["assets", index],
      message: `${asset.path}: expected ${asset.width}x${asset.height}, found ${png.width}x${png.height}`,
    });
  }
  if (asset.release && png.colorSpace !== "sRGB") {
    pushUnique(issues, {
      code: "RASTER_COLORSPACE",
      path: ["assets", index],
      message: `${asset.path}: release PNG requires an explicit sRGB chunk`,
    });
  }
  if (asset.alpha === "transparent-corners") {
    if (!png.hasAlpha || png.cornerAlphas.some((alpha) => alpha !== 0)) {
      pushUnique(issues, {
        code: "RASTER_ALPHA_MISMATCH",
        path: ["assets", index, "alpha"],
        message: `${asset.path}: all four corners must be fully transparent`,
      });
    }
  } else if (asset.alpha === "opaque" && !png.isFullyOpaque) {
    pushUnique(issues, {
      code: "RASTER_ALPHA_MISMATCH",
      path: ["assets", index, "alpha"],
      message: `${asset.path}: the complete image must be opaque`,
    });
  }
  if (asset.release && bytes.byteLength >= MAX_RELEASE_RASTER_BYTES) {
    pushUnique(issues, {
      code: "RASTER_FILE_TOO_LARGE",
      path: ["assets", index, "path"],
      message: `${asset.path}: release raster must be smaller than 6 MiB`,
    });
  }
}

function unfilterRow(
  source: Uint8Array,
  previous: Uint8Array,
  bytesPerPixel: number,
  filter: number,
): Uint8Array {
  const output = new Uint8Array(source.byteLength);
  for (let index = 0; index < source.byteLength; index += 1) {
    const left = index >= bytesPerPixel ? output[index - bytesPerPixel] ?? 0 : 0;
    const up = previous[index] ?? 0;
    const upLeft = index >= bytesPerPixel ? previous[index - bytesPerPixel] ?? 0 : 0;
    const byte = source[index] ?? 0;
    const predictor =
      filter === 0
        ? 0
        : filter === 1
          ? left
          : filter === 2
            ? up
            : filter === 3
              ? Math.floor((left + up) / 2)
              : filter === 4
                ? paeth(left, up, upLeft)
                : -1;
    if (predictor < 0) throw new TypeError(`Unsupported PNG filter ${filter}`);
    output[index] = (byte + predictor) & 0xff;
  }
  return output;
}

function paeth(left: number, up: number, upLeft: number): number {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const diagonalDistance = Math.abs(estimate - upLeft);
  return leftDistance <= upDistance && leftDistance <= diagonalDistance
    ? left
    : upDistance <= diagonalDistance
      ? up
      : upLeft;
}

async function findReleaseFiles(root: string): Promise<string[]> {
  const results: string[] = [];
  for (const relativeRoot of ["assets/ui", "assets/art", "assets/audio"]) {
    const absoluteRoot = path.join(root, relativeRoot);
    if (!(await isDirectory(absoluteRoot))) continue;
    for (const absolutePath of await walkFiles(absoluteRoot)) {
      if (RELEASE_EXTENSIONS.has(path.extname(absolutePath).toLowerCase())) {
        results.push(toRepositoryPath(root, absolutePath));
      }
    }
  }
  return results.sort();
}

async function findCandidateReferences(root: string): Promise<string[]> {
  const results: string[] = [];
  const roots = ["content", "resources", "scenes", "src"];
  for (const relativeRoot of roots) {
    const absoluteRoot = path.join(root, relativeRoot);
    if (!(await isDirectory(absoluteRoot))) continue;
    for (const absolutePath of await walkFiles(absoluteRoot)) {
      if (!CONSUMER_EXTENSIONS.has(path.extname(absolutePath).toLowerCase())) continue;
      const text = await readFile(absolutePath, "utf8");
      if (text.includes("assets/source/")) results.push(toRepositoryPath(root, absolutePath));
    }
  }
  const projectFile = path.join(root, "project.godot");
  if (await isFile(projectFile)) {
    const text = await readFile(projectFile, "utf8");
    if (text.includes("assets/source/")) results.push("project.godot");
  }
  return results.sort();
}

async function walkFiles(directory: string): Promise<string[]> {
  const output: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...(await walkFiles(child)));
    else if (entry.isFile()) output.push(child);
  }
  return output;
}

function linkedPaths(asset: AssetRecord): Array<[string, string]> {
  const output: Array<[string, string]> = [["source_path", asset.source_path]];
  if (asset.master_path) output.push(["master_path", asset.master_path]);
  if (asset.prompt_path) output.push(["prompt_path", asset.prompt_path]);
  if (asset.generation_script) output.push(["generation_script", asset.generation_script]);
  if (asset.input_path && asset.input_path !== asset.source_path) output.push(["input_path", asset.input_path]);
  return output;
}

function isSafeRepositoryPath(candidate: string): boolean {
  if (candidate.includes("\\") || candidate.includes("\0") || path.posix.isAbsolute(candidate)) return false;
  if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(candidate)) return false;
  const normalized = path.posix.normalize(candidate);
  return normalized === candidate && !candidate.startsWith("../") && !candidate.includes("/../");
}

function resolveSafe(root: string, relativePath: string): string | undefined {
  if (!isSafeRepositoryPath(relativePath)) return undefined;
  const resolved = path.resolve(root, relativePath);
  return resolved.startsWith(`${root}${path.sep}`) ? resolved : undefined;
}

async function isFile(candidate: string): Promise<boolean> {
  try {
    return (await stat(candidate)).isFile();
  } catch {
    return false;
  }
}

async function isDirectory(candidate: string): Promise<boolean> {
  try {
    return (await stat(candidate)).isDirectory();
  } catch {
    return false;
  }
}

function toRepositoryPath(root: string, absolutePath: string): string {
  return path.relative(root, absolutePath).split(path.sep).join("/");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function pushUnique(issues: AssetIssue[], issue: AssetIssue): void {
  const key = `${issue.code}:${issue.path.join(".")}:${issue.message}`;
  if (!issues.some((candidate) => `${candidate.code}:${candidate.path.join(".")}:${candidate.message}` === key)) {
    issues.push(issue);
  }
}

function report(issues: readonly AssetIssue[]): AssetReport {
  return { ok: issues.length === 0, issues };
}

function parseArguments(argv: readonly string[]): { manifestPath: string; licensesPath: string } {
  let manifestPath = "assets/asset-manifest.json";
  let licensesPath = "ASSET_LICENSES.md";
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--manifest" && argv[index + 1]) manifestPath = argv[++index]!;
    else if (argument === "--licenses" && argv[index + 1]) licensesPath = argv[++index]!;
    else throw new TypeError(`Unknown or incomplete argument: ${argument ?? ""}`);
  }
  return { manifestPath, licensesPath };
}

async function main(): Promise<void> {
  try {
    const args = parseArguments(process.argv.slice(2));
    const root = process.cwd();
    const result = await validateAssetWorkspace({
      root,
      manifestPath: path.resolve(root, args.manifestPath),
      licensesPath: path.resolve(root, args.licensesPath),
    });
    if (!result.ok) {
      for (const issue of result.issues) {
        console.error(`${issue.code} ${issue.path.join(".")}: ${issue.message}`);
      }
      process.exitCode = 1;
      return;
    }
    const manifest = AssetManifestSchema.parse(
      JSON.parse(await readFile(path.resolve(root, args.manifestPath), "utf8")),
    );
    const releaseCount = manifest.assets.filter((asset) => asset.release).length;
    console.log(`Validated ${manifest.assets.length} asset records (${releaseCount} release assets)`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Asset validation failed");
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  void main();
}
