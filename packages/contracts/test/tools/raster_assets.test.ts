import { readFile } from "node:fs/promises";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { inspectPng, validateAssetWorkspace } from "../../../../tools/assets/validate_assets.js";

const ROOT = path.resolve(new URL("../../../..", import.meta.url).pathname);

const RASTERS = [
  ["assets/art/moa/moa_neutral.png", 1024, 1024, "transparent-corners"],
  ["assets/art/moa/moa_celebrate.png", 1024, 1024, "transparent-corners"],
  ["assets/art/moa/moa_encourage.png", 1024, 1024, "transparent-corners"],
  ["assets/art/moa/moa_point.png", 1024, 1024, "transparent-corners"],
  ["assets/art/island/exploration_island_bg.png", 1080, 1920, "opaque"],
  ["assets/art/collection/collection_shells.png", 2048, 2048, "transparent-corners"],
] as const;

describe("release raster art", () => {
  it("uses exact sRGB PNG dimensions, alpha edges, and the 6 MiB budget", async () => {
    for (const [relativePath, width, height, alpha] of RASTERS) {
      const bytes = await readFile(path.join(ROOT, relativePath));
      const png = inspectPng(bytes);
      expect(png.width, relativePath).toBe(width);
      expect(png.height, relativePath).toBe(height);
      expect(png.colorSpace, relativePath).toBe("sRGB");
      expect(bytes.byteLength, relativePath).toBeLessThan(6 * 1024 * 1024);
      if (alpha === "transparent-corners") {
        expect(png.hasAlpha, relativePath).toBe(true);
        expect(png.cornerAlphas, relativePath).toEqual([0, 0, 0, 0]);
      } else {
        expect(png.isFullyOpaque, relativePath).toBe(true);
      }
    }
  });

  it("keeps exact generated prompt/source linkage and complete release review", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as {
      assets: Array<{
        path: string;
        release: boolean;
        origin: string;
        source_path?: string;
        prompt_path?: string;
        reviewer: string;
        review: Record<string, boolean>;
      }>;
    };
    for (const [relativePath] of RASTERS) {
      const record = manifest.assets.find((asset) => asset.path === relativePath);
      expect(record?.release, relativePath).toBe(true);
      expect(record?.origin, relativePath).toBe("generated-derived");
      expect(record?.source_path, relativePath).toMatch(/^assets\/source\/art\/generated\/.+\.png$/);
      expect(record?.prompt_path, relativePath).toMatch(/^assets\/source\/prompts\/.+\.md$/);
      expect(record?.reviewer.trim(), relativePath).not.toBe("");
      expect(Object.values(record?.review ?? {}), relativePath).not.toContain(false);
    }
    expect(manifest.assets.filter((asset) => asset.path.includes("/source/art/generated/"))).toSatisfy(
      (records: typeof manifest.assets) => records.every((record) => record.release === false),
    );
  });

  it("passes the complete manifest admission gate", async () => {
    const report = await validateAssetWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/asset-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
    });
    expect(report.issues).toEqual([]);
  });
});
