import { createHash } from "node:crypto";
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

const MOA_POSES = {
  neutral: {
    sourceSha256: "bb91c5ee4b3f3e94d2bb8ad17dd4ccd6cbcd4c6487f40038d7d224c4dce5135f",
    primaryRequest: "calm neutral standing pose",
    pose: "both paws relaxed near the satchel strap",
  },
  celebrate: {
    sourceSha256: "e2cea9f78f11723c25b1fb43a4b14d6220c61e34125431d679ae59830313cd82",
    primaryRequest: "joyful celebration pose",
    pose: "both paws raised upward in a delighted cheer",
  },
  encourage: {
    sourceSha256: "0386818ca4e3a0b1ad71eb6956ff32be1bbdea419bea4251e2b5c7f19a5ef56a",
    primaryRequest: "gentle encouraging pose for a child after a mistake",
    pose: "one paw resting warmly over the chest",
  },
  point: {
    sourceSha256: "524572f4a3553caa6ef79644c32072c2b4bc4b5bbdaafca0e0c4532ae336bef3",
    primaryRequest: "clear teaching pose that points toward a nearby learning object",
    pose: "one arm extended sideways",
  },
} as const;

interface Transformation {
  source_width: number;
  source_height: number;
  output_width: number;
  output_height: number;
  operations: string[];
}

interface ManifestAsset {
  id: string;
  path: string;
  release: boolean;
  origin: string;
  source_path?: string;
  master_path?: string;
  prompt_path?: string;
  prompt_sha256?: string;
  sha256: string;
  modifications: string;
  transformation?: Transformation;
  reviewer: string;
  review: Record<string, boolean>;
}

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
    ) as { assets: ManifestAsset[] };
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

  it("links every Moa pose to its exact distinct prompt and genuine source master", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: ManifestAsset[] };
    const releaseRecords = Object.keys(MOA_POSES).map((pose) => {
      const pathName = `assets/art/moa/moa_${pose}.png`;
      const record = manifest.assets.find((candidate) => candidate.path === pathName);
      expect(record, pathName).toBeDefined();
      return record!;
    });
    expect(new Set(releaseRecords.map((record) => record.prompt_path)).size).toBe(4);
    expect(new Set(releaseRecords.map((record) => record.source_path)).size).toBe(4);
    expect(new Set(releaseRecords.map((record) => record.master_path)).size).toBe(4);

    for (const [pose, expected] of Object.entries(MOA_POSES)) {
      const releasePath = `assets/art/moa/moa_${pose}.png`;
      const sourcePath = `assets/source/art/generated/moa-${pose}-v1.png`;
      const promptPath = `assets/source/prompts/moa-${pose}-v1.md`;
      const release = manifest.assets.find((record) => record.path === releasePath)!;
      expect(release.source_path, pose).toBe(sourcePath);
      expect(release.master_path, pose).toBe(sourcePath);
      expect(release.master_path, pose).not.toBe(release.path);
      expect(release.prompt_path, pose).toBe(promptPath);

      const source = manifest.assets.find((record) => record.path === sourcePath);
      expect(source?.release, pose).toBe(false);
      expect(source?.prompt_path, pose).toBe(promptPath);
      const sourceBytes = await readFile(path.join(ROOT, sourcePath));
      expect(createHash("sha256").update(sourceBytes).digest("hex"), pose).toBe(
        expected.sourceSha256,
      );
      expect(source?.sha256, pose).toBe(expected.sourceSha256);
      expect(inspectPng(sourceBytes), pose).toMatchObject({ width: 1254, height: 1254 });

      const prompt = await readFile(path.join(ROOT, promptPath), "utf8");
      expect(prompt, pose).toContain(expected.primaryRequest);
      expect(prompt, pose).toContain(expected.pose);
      const promptHash = createHash("sha256").update(prompt).digest("hex");
      expect(release.prompt_sha256, pose).toBe(promptHash);
      expect(source?.prompt_sha256, pose).toBe(promptHash);
      expect(release.transformation, pose).toEqual({
        source_width: 1254,
        source_height: 1254,
        output_width: 1024,
        output_height: 1024,
        operations: [
          "remove-chroma-key",
          "despill",
          "convert-rgba",
          "resize-lanczos",
          "optimize-png",
          "add-srgb-chunk",
        ],
      });
    }
  });

  it("declares the exact island resize instead of a crop or unchanged pixels", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: ManifestAsset[] };
    const island = manifest.assets.find((asset) => asset.id === "art.island.exploration_bg");
    expect(island?.master_path).toBe("assets/source/art/generated/exploration-island-v1.png");
    expect(island?.transformation).toEqual({
      source_width: 941,
      source_height: 1672,
      output_width: 1080,
      output_height: 1920,
      operations: ["resize-lanczos", "optimize-png", "add-srgb-chunk"],
    });
    expect(island?.modifications).toMatch(/resize/i);
    expect(island?.modifications).not.toMatch(/crop|without pixel changes/i);
  });

  it("declares the exact collection alpha-clean, resize, and padding chain", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: ManifestAsset[] };
    const collection = manifest.assets.find((asset) => asset.id === "art.collection.shells");
    expect(collection?.master_path).toBe(
      "assets/source/art/generated/collection-shells-keyed-v1.png",
    );
    expect(collection?.transformation).toEqual({
      source_width: 1448,
      source_height: 1086,
      output_width: 2048,
      output_height: 2048,
      operations: [
        "remove-chroma-key",
        "despill",
        "resize-lanczos",
        "pad-transparent",
        "optimize-png",
        "add-srgb-chunk",
      ],
    });
    expect(collection?.modifications).toMatch(/1920x1440.*2048x2048/i);
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
