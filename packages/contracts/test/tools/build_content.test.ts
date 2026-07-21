import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  buildContent,
  createContentBundle,
  readSourceDrafts,
  type ContentBuildOptions,
} from "../../../../tools/content/build_content.js";
import { validateContentOnDisk } from "../../../../tools/content/validate_content.js";

const REPOSITORY_ROOT = resolve(dirname(new URL(import.meta.url).pathname), "../../../..");
const METADATA = {
  contentVersion: "1.0.0",
  manifestVersion: "1.0.0",
  publishedAt: "2026-07-21T00:00:00.000Z",
} as const;
const temporaryRoots: string[] = [];

function temporaryRepository(): string {
  const rootDir = mkdtempSync(join(tmpdir(), "mathland-content-build-"));
  temporaryRoots.push(rootDir);
  mkdirSync(join(rootDir, "content"), { recursive: true });
  cpSync(join(REPOSITORY_ROOT, "content", "sources"), join(rootDir, "content", "sources"), {
    recursive: true,
  });
  return rootDir;
}

function options(rootDir: string, extra: Partial<ContentBuildOptions> = {}): ContentBuildOptions {
  return { rootDir, ...METADATA, ...extra };
}

function generatedSnapshot(rootDir: string): Map<string, string> {
  const result = new Map<string, string>();
  const visit = (relativePath: string): void => {
    const absolutePath = join(rootDir, relativePath);
    if (!existsSync(absolutePath)) return;
    for (const entry of readdirSync(absolutePath, { withFileTypes: true })) {
      const child = join(relativePath, entry.name);
      if (entry.isDirectory()) visit(child);
      else result.set(child, readFileSync(join(rootDir, child), "utf8"));
    }
  };
  visit("content/packages");
  visit("content/manifests");
  const activePath = join(rootDir, "content", "active-manifest.json");
  if (existsSync(activePath)) result.set("content/active-manifest.json", readFileSync(activePath, "utf8"));
  return result;
}

afterEach(() => {
  for (const rootDir of temporaryRoots.splice(0)) {
    rmSync(rootDir, { recursive: true, force: true });
  }
});

describe("immutable content bundle", () => {
  it("is byte-identical regardless of source discovery order", () => {
    const sources = readSourceDrafts(REPOSITORY_ROOT);
    const forward = createContentBundle(sources, METADATA);
    const reverse = createContentBundle([...sources].reverse(), METADATA);
    expect([...forward.files]).toEqual([...reverse.files]);
    expect(forward.summary).toEqual({ activities: 11, bands: 33, samples: 132 });
  });

  it("builds exactly 11 checksummed packages and passes a no-drift rebuild", async () => {
    const rootDir = temporaryRepository();
    const built = await buildContent(options(rootDir));
    expect(built).toEqual({ activities: 11, bands: 33, samples: 132, checked: false });
    expect(await buildContent(options(rootDir, { check: true }))).toEqual({
      activities: 11,
      bands: 33,
      samples: 132,
      checked: true,
    });
    expect(validateContentOnDisk({ rootDir })).toEqual({ activities: 11, bands: 33, samples: 132 });
    expect(generatedSnapshot(rootDir).size).toBe(13);
  });

  it("detects drift without mutating generated files", async () => {
    const rootDir = temporaryRepository();
    await buildContent(options(rootDir));
    const packagePath = join(rootDir, "content/packages/addition_ones/1.0.0.json");
    writeFileSync(packagePath, `${readFileSync(packagePath, "utf8")} `, "utf8");
    const before = generatedSnapshot(rootDir);
    await expect(buildContent(options(rootDir, { check: true }))).rejects.toThrow(/drift/i);
    expect(generatedSnapshot(rootDir)).toEqual(before);
  });

  it("leaves the previous bundle untouched when a staged source is invalid", async () => {
    const rootDir = temporaryRepository();
    await buildContent(options(rootDir));
    const before = generatedSnapshot(rootDir);
    const sourcePath = join(rootDir, "content/sources/addition_ones.json");
    const invalid = JSON.parse(readFileSync(sourcePath, "utf8")) as Record<string, unknown>;
    invalid.activity_id = "unknown_activity";
    writeFileSync(sourcePath, JSON.stringify(invalid), "utf8");
    await expect(buildContent(options(rootDir))).rejects.toThrow(/addition_ones|activity/i);
    expect(generatedSnapshot(rootDir)).toEqual(before);
  });

  it("rejects missing, traversing, unknown, and corrupted catalogue inputs", async () => {
    const mutateAndValidate = async (mutate: (rootDir: string) => void, pattern: RegExp): Promise<void> => {
      const rootDir = temporaryRepository();
      await buildContent(options(rootDir));
      mutate(rootDir);
      expect(() => validateContentOnDisk({ rootDir })).toThrow(pattern);
    };

    await mutateAndValidate(
      (rootDir) => rmSync(join(rootDir, "content/packages/addition_ones/1.0.0.json")),
      /missing|read/i,
    );
    await mutateAndValidate((rootDir) => {
      const manifestPath = join(rootDir, "content/active-manifest.json");
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
        packages: Array<Record<string, unknown>>;
      };
      manifest.packages[0]!.path = "../../outside.json";
      writeFileSync(manifestPath, JSON.stringify(manifest), "utf8");
    }, /path|manifest/i);
    await mutateAndValidate((rootDir) => {
      const manifestPath = join(rootDir, "content/active-manifest.json");
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
        packages: Array<Record<string, unknown>>;
      };
      manifest.packages[0]!.activity_id = "unknown_activity";
      writeFileSync(manifestPath, JSON.stringify(manifest), "utf8");
    }, /activity|manifest/i);
    await mutateAndValidate((rootDir) => {
      const packagePath = join(rootDir, "content/packages/addition_ones/1.0.0.json");
      const activity = JSON.parse(readFileSync(packagePath, "utf8")) as {
        localizations: { "ko-KR": { title: string } };
      };
      activity.localizations["ko-KR"].title = "tampered";
      writeFileSync(packagePath, JSON.stringify(activity), "utf8");
    }, /checksum|package/i);
  });
});
