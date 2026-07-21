import { readFile } from "node:fs/promises";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { REQUIRED_RELEASE_SVGS } from "../../../../tools/assets/asset_schema.js";
import { validateSvgText } from "../../../../tools/assets/validate_svg.js";

const ROOT = path.resolve(new URL("../../../..", import.meta.url).pathname);
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

const EXPECTED = [
  "assets/ui/icons/activities/addition_ones.svg",
  "assets/ui/icons/activities/subtraction_ones.svg",
  "assets/ui/icons/activities/multiplication.svg",
  "assets/ui/icons/activities/common_multiples_lcm.svg",
  "assets/ui/icons/activities/prime_factorization.svg",
  "assets/ui/icons/activities/foundations_counting.svg",
  "assets/ui/icons/activities/foundations_number_bonds.svg",
  "assets/ui/icons/activities/foundations_ten_frame.svg",
  "assets/ui/icons/activities/foundations_base_ten.svg",
  "assets/ui/icons/activities/foundations_number_line.svg",
  "assets/ui/icons/activities/foundations_basic_operations.svg",
  "assets/ui/icons/status/correct.svg",
  "assets/ui/icons/status/wrong.svg",
  "assets/ui/icons/status/heart.svg",
  "assets/ui/icons/status/speaker.svg",
  "assets/ui/learning/ten_frame.svg",
  "assets/ui/learning/ten_rod.svg",
  "assets/ui/learning/unit_cube.svg",
  "assets/ui/learning/number_line_marker.svg",
] as const;

describe("release SVG set", () => {
  it("keeps the exact required 19 paths", () => {
    expect(REQUIRED_RELEASE_SVGS).toEqual(EXPECTED);
  });

  it("contains accessible, text-free, palette-only vectors in the manifest and license ledger", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: { id: string; path: string; release: boolean }[] };
    const licenses = await readFile(path.join(ROOT, "ASSET_LICENSES.md"), "utf8");

    for (const relativePath of EXPECTED) {
      const svg = await readFile(path.join(ROOT, relativePath), "utf8");
      const expectedViewBox = relativePath.includes("/learning/")
        ? "0 0 256 256"
        : "0 0 128 128";
      expect(validateSvgText(svg, { expectedViewBox, palette: PALETTE }), relativePath).toEqual([]);
      expect(svg, relativePath).toContain('stroke="#23415A"');
      expect(svg, relativePath).toContain('stroke-width="8"');
      const record = manifest.assets.find((asset) => asset.path === relativePath);
      expect(record?.release, relativePath).toBe(true);
      expect(licenses, relativePath).toContain(`\`${record?.id}\``);
    }
  });
});
