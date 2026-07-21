import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  validateAssetManifest,
  validateAssetWorkspace,
} from "../../../../tools/assets/validate_assets.js";
import { validateSvgText } from "../../../../tools/assets/validate_svg.js";

const PALETTE = [
  "#66D3B5",
  "#76C8F0",
  "#F4D9A4",
  "#FF8A7A",
  "#E94B4B",
  "#F6C453",
  "#23415A",
  "#FFF8E8",
] as const;

const VALID_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" role="img" aria-labelledby="title desc">
  <title id="title">Safe icon</title>
  <desc id="desc">A safe shape</desc>
  <circle cx="64" cy="64" r="40" fill="#66D3B5" stroke="#23415A" stroke-width="8"/>
</svg>`;

function hash(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function svgRecord(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "ui.test.safe",
    path: "assets/ui/icons/test.svg",
    kind: "svg",
    release: true,
    width: 128,
    height: 128,
    view_box: "0 0 128 128",
    alpha: "vector",
    origin: "original",
    creator: "Jinho Park",
    tool: "project-native SVG",
    source_path: "assets/ui/icons/test.svg",
    sha256: hash(VALID_SVG),
    license: "MathLand-Original-1.0",
    modifications: "Original vector artwork.",
    redistribution: "confirmed",
    reviewer: "Codex visual review",
    review_date: "2026-07-21",
    review: {
      math_correct: true,
      text_absent: true,
      transparency_correct: true,
      artifacts_absent: true,
      child_appropriate: true,
      silhouette_clear: true,
      contrast_checked: true,
      legible_48dp: true,
    },
    ...overrides,
  };
}

function generatedPngRecord(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const record = svgRecord({
    id: "art.test.generated",
    path: "assets/art/test.png",
    kind: "png",
    width: 1024,
    height: 1024,
    alpha: "transparent-corners",
    origin: "generated-derived",
    creator: "OpenAI built-in image_gen",
    tool: "OpenAI built-in image_gen",
    source_path: "assets/source/art/generated/test-v1.png",
    master_path: "assets/source/art/generated/test-v1.png",
    prompt_path: "assets/source/prompts/test-v1.md",
    prompt_sha256: "a".repeat(64),
    generation_date: "2026-07-21",
    transformation: {
      source_width: 1254,
      source_height: 1254,
      output_width: 1024,
      output_height: 1024,
      operations: ["remove-chroma-key", "resize-lanczos", "add-srgb-chunk"],
    },
    ...overrides,
  });
  delete record.view_box;
  return record;
}

function manifest(assets: readonly unknown[]): Record<string, unknown> {
  return {
    manifest_version: "1.0.0",
    generated_at: "2026-07-21",
    palette: PALETTE,
    assets,
  };
}

function issueCodes(report: { issues: readonly { code: string }[] }): string[] {
  return report.issues.map((issue) => issue.code);
}

describe("asset provenance schema", () => {
  it.each([
    ["origin", "PROVENANCE_REQUIRED"],
    ["license", "LICENSE_REQUIRED"],
    ["redistribution", "RIGHTS_REQUIRED"],
  ])("rejects a missing %s field", (field, code) => {
    const record = svgRecord();
    delete record[field];
    expect(issueCodes(validateAssetManifest(manifest([record])))).toContain(code);
  });

  it("rejects duplicate IDs and duplicate paths", () => {
    const report = validateAssetManifest(manifest([svgRecord(), svgRecord()]));
    expect(issueCodes(report)).toEqual(expect.arrayContaining(["DUPLICATE_ID", "DUPLICATE_PATH"]));
  });

  it("rejects traversal, absolute, and URL paths", () => {
    for (const candidate of ["../outside.svg", "/tmp/outside.svg", "https://bad.test/icon.svg"]) {
      expect(issueCodes(validateAssetManifest(manifest([svgRecord({ path: candidate })])))).toContain(
        "UNSAFE_PATH",
      );
    }
  });

  it("rejects any release record without confirmed redistribution rights", () => {
    const report = validateAssetManifest(
      manifest([
        svgRecord({
          id: "audio.test",
          path: "assets/audio/test.ogg",
          kind: "audio",
          release: true,
          redistribution: "unconfirmed",
        }),
      ]),
    );
    expect(issueCodes(report)).toContain("RELEASE_RIGHTS_UNCONFIRMED");
  });

  it("requires generated records to pin the prompt hash and generation date", () => {
    const report = validateAssetManifest(
      manifest([
        svgRecord({
          origin: "generated-derived",
          prompt_path: "assets/source/prompts/icon.md",
          master_path: "assets/ui/icons/test.svg",
        }),
      ]),
    );
    expect(issueCodes(report)).toContain("ASSET_SCHEMA_INVALID");
  });

  it("rejects a generated master that aliases its release output", () => {
    const record = generatedPngRecord({ master_path: "assets/art/test.png" });
    expect(issueCodes(validateAssetManifest(manifest([record])))).toContain(
      "GENERATED_MASTER_INVALID",
    );
  });

  it("rejects transformation output dimensions that contradict the release record", () => {
    const record = generatedPngRecord({
      transformation: {
        source_width: 1254,
        source_height: 1254,
        output_width: 1080,
        output_height: 1024,
        operations: ["resize-lanczos"],
      },
    });
    expect(issueCodes(validateAssetManifest(manifest([record])))).toContain(
      "RASTER_TRANSFORMATION_INVALID",
    );
  });
});

describe("safe SVG gate", () => {
  it("accepts project-native accessible palette SVG", () => {
    expect(validateSvgText(VALID_SVG, { expectedViewBox: "0 0 128 128", palette: PALETTE })).toEqual(
      [],
    );
  });

  it.each([
    ["script", VALID_SVG.replace("</svg>", "<script>alert(1)</script></svg>"), "SVG_SCRIPT"],
    ["event", VALID_SVG.replace("<circle", "<circle onclick=\"alert(1)\""), "SVG_EVENT_ATTRIBUTE"],
    [
      "remote reference",
      VALID_SVG.replace("</svg>", "<use href=\"https://bad.test/x.svg#x\"/></svg>"),
      "SVG_REMOTE_REFERENCE",
    ],
    [
      "relative external reference",
      VALID_SVG.replace("</svg>", "<use href=\"other.svg#shape\"/></svg>"),
      "SVG_REMOTE_REFERENCE",
    ],
    [
      "embedded raster",
      VALID_SVG.replace("</svg>", "<image href=\"data:image/png;base64,AA==\"/></svg>"),
      "SVG_EMBEDDED_RASTER",
    ],
    ["rendered text", VALID_SVG.replace("</svg>", "<text>7</text></svg>"), "SVG_RENDERED_TEXT"],
    [
      "wrong viewBox",
      VALID_SVG.replace('viewBox="0 0 128 128"', 'viewBox="0 0 64 64"'),
      "SVG_VIEWBOX",
    ],
    ["outside color", VALID_SVG.replace("#66D3B5", "#000000"), "SVG_PALETTE"],
  ])("rejects %s", (_label, svg, code) => {
    const issues = validateSvgText(svg, { expectedViewBox: "0 0 128 128", palette: PALETTE });
    expect(issues.map((issue) => issue.code)).toContain(code);
  });
});

describe("asset workspace admission", () => {
  async function createWorkspace(): Promise<{
    root: string;
    manifestPath: string;
    licensesPath: string;
    manifestValue: Record<string, unknown>;
  }> {
    const root = await mkdtemp(path.join(tmpdir(), "mathland-assets-"));
    const svgPath = path.join(root, "assets/ui/icons/test.svg");
    await mkdir(path.dirname(svgPath), { recursive: true });
    await writeFile(svgPath, VALID_SVG, "utf8");
    const manifestPath = path.join(root, "assets/asset-manifest.json");
    const licensesPath = path.join(root, "ASSET_LICENSES.md");
    const manifestValue = manifest([svgRecord()]);
    await writeFile(manifestPath, JSON.stringify(manifestValue), "utf8");
    await writeFile(licensesPath, "# Licenses\n\n- `ui.test.safe` — MathLand-Original-1.0\n", "utf8");
    return { root, manifestPath, licensesPath, manifestValue };
  }

  it("accepts a bijective, hashed, licensed workspace", async () => {
    const fixture = await createWorkspace();
    expect(await validateAssetWorkspace(fixture)).toEqual({ ok: true, issues: [] });
  });

  it("rejects missing and unlisted release files", async () => {
    const fixture = await createWorkspace();
    await writeFile(path.join(fixture.root, "assets/ui/icons/unlisted.svg"), VALID_SVG, "utf8");
    const withUnlisted = await validateAssetWorkspace(fixture);
    expect(issueCodes(withUnlisted)).toContain("UNLISTED_RELEASE_FILE");

    const value = JSON.parse(await readFile(fixture.manifestPath, "utf8")) as Record<string, unknown>;
    (value.assets as Record<string, unknown>[])[0]!.path = "assets/ui/icons/missing.svg";
    await writeFile(fixture.manifestPath, JSON.stringify(value), "utf8");
    expect(issueCodes(await validateAssetWorkspace(fixture))).toContain("MISSING_ASSET_FILE");
  });

  it("rejects hash drift and an absent license ledger entry", async () => {
    const fixture = await createWorkspace();
    const value = JSON.parse(await readFile(fixture.manifestPath, "utf8")) as Record<string, unknown>;
    (value.assets as Record<string, unknown>[])[0]!.sha256 = "0".repeat(64);
    await writeFile(fixture.manifestPath, JSON.stringify(value), "utf8");
    await writeFile(fixture.licensesPath, "# Licenses\n", "utf8");
    const codes = issueCodes(await validateAssetWorkspace(fixture));
    expect(codes).toEqual(expect.arrayContaining(["HASH_MISMATCH", "LICENSE_LEDGER_MISSING"]));
  });

  it("rejects release content that directly references a non-release candidate", async () => {
    const fixture = await createWorkspace();
    await mkdir(path.join(fixture.root, "content"), { recursive: true });
    await writeFile(
      path.join(fixture.root, "content/bad.json"),
      '{"texture":"assets/source/art/generated/candidate.png"}',
      "utf8",
    );
    expect(issueCodes(await validateAssetWorkspace(fixture))).toContain(
      "RELEASE_REFERENCES_CANDIDATE",
    );
  });

  it("rejects raster dimension and alpha declarations that differ from the PNG", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "mathland-raster-"));
    const source = await readFile(
      new URL("../../../../assets/art/moa/moa_neutral.png", import.meta.url),
    );
    const assetPath = path.join(root, "assets/art/test.png");
    await mkdir(path.dirname(assetPath), { recursive: true });
    await writeFile(assetPath, source);
    const record = {
      ...svgRecord({
        id: "art.test.bad_metadata",
        path: "assets/art/test.png",
        kind: "png",
        width: 1,
        height: 1,
        alpha: "opaque",
        source_path: "assets/art/test.png",
        sha256: createHash("sha256").update(source).digest("hex"),
      }),
    };
    delete record.view_box;
    const manifestPath = path.join(root, "assets/asset-manifest.json");
    const licensesPath = path.join(root, "ASSET_LICENSES.md");
    await writeFile(manifestPath, JSON.stringify(manifest([record])), "utf8");
    await writeFile(
      licensesPath,
      "# Licenses\n\n- `art.test.bad_metadata` — MathLand-Original-1.0\n",
      "utf8",
    );
    const codes = issueCodes(
      await validateAssetWorkspace({ root, manifestPath, licensesPath }),
    );
    expect(codes).toEqual(
      expect.arrayContaining(["RASTER_DIMENSION_MISMATCH", "RASTER_ALPHA_MISMATCH"]),
    );
  });
});
