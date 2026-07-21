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

function elements(svg: string, tag: string, className: string): string[] {
  const pattern = new RegExp(`<${tag}\\b[^>]*\\bclass="${className}"[^>]*/?>`, "g");
  return [...svg.matchAll(pattern)].map((match) => match[0]);
}

function elementById(svg: string, tag: string, id: string): string {
  const match = svg.match(new RegExp(`<${tag}\\b[^>]*\\bid="${id}"[^>]*/?>`));
  expect(match, `missing ${tag}#${id}`).not.toBeNull();
  return match?.[0] ?? "";
}

function numberAttribute(element: string, name: string): number {
  const match = element.match(new RegExp(`\\b${name}="(-?[0-9]+(?:\\.[0-9]+)?)"`));
  expect(match, `${element} has no numeric ${name}`).not.toBeNull();
  return Number(match?.[1]);
}

function pathData(element: string): string {
  const match = element.match(/\bd="([^"]+)"/);
  expect(match, `${element} has no path data`).not.toBeNull();
  return match?.[1] ?? "";
}

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

  it("depicts one square 10x10 hundred flat and one ten-section rod", async () => {
    const svg = await readFile(
      path.join(ROOT, "assets/ui/icons/activities/foundations_base_ten.svg"),
      "utf8",
    );
    const flat = elementById(svg, "rect", "hundred-flat-outline");
    const flatX = numberAttribute(flat, "x");
    const flatY = numberAttribute(flat, "y");
    const flatWidth = numberAttribute(flat, "width");
    const flatHeight = numberAttribute(flat, "height");
    expect(flatWidth).toBe(flatHeight);
    expect(flatWidth).toBeGreaterThanOrEqual(64);

    const columns = elements(svg, "line", "hundred-column-divider");
    const rows = elements(svg, "line", "hundred-row-divider");
    expect(columns).toHaveLength(9);
    expect(rows).toHaveLength(9);
    columns.forEach((line, index) => {
      expect(numberAttribute(line, "x1")).toBeCloseTo(
        flatX + (flatWidth / 10) * (index + 1),
        5,
      );
      expect(numberAttribute(line, "x2")).toBe(numberAttribute(line, "x1"));
      expect(numberAttribute(line, "y1")).toBe(flatY);
      expect(numberAttribute(line, "y2")).toBe(flatY + flatHeight);
      expect(numberAttribute(line, "stroke-width")).toBeGreaterThanOrEqual(1.5);
    });
    rows.forEach((line, index) => {
      expect(numberAttribute(line, "y1")).toBeCloseTo(
        flatY + (flatHeight / 10) * (index + 1),
        5,
      );
      expect(numberAttribute(line, "y2")).toBe(numberAttribute(line, "y1"));
      expect(numberAttribute(line, "x1")).toBe(flatX);
      expect(numberAttribute(line, "x2")).toBe(flatX + flatWidth);
    });

    const rod = elementById(svg, "rect", "ten-rod-outline");
    const rodY = numberAttribute(rod, "y");
    const rodHeight = numberAttribute(rod, "height");
    expect(rodHeight).toBeGreaterThanOrEqual(64);
    const rodDividers = elements(svg, "line", "ten-rod-divider");
    expect(rodDividers).toHaveLength(9);
    rodDividers.forEach((line, index) => {
      expect(numberAttribute(line, "y1")).toBeCloseTo(
        rodY + (rodHeight / 10) * (index + 1),
        5,
      );
      expect(numberAttribute(line, "y2")).toBe(numberAttribute(line, "y1"));
    });
    expect(elements(svg, "rect", "unit-cube")).toHaveLength(2);
  });

  it("depicts exactly three equal consecutive number-line hops", async () => {
    const svg = await readFile(
      path.join(ROOT, "assets/ui/icons/activities/foundations_number_line.svg"),
      "utf8",
    );
    const ticks = elements(svg, "line", "number-line-tick").map((line) =>
      numberAttribute(line, "x1"),
    );
    expect(ticks).toEqual([24, 48, 72, 96]);

    const hops = elements(svg, "path", "number-line-hop").map((path) => {
      const match = pathData(path).match(
        /^M([0-9.]+) ([0-9.]+)Q([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+)$/,
      );
      expect(match, `unexpected hop geometry: ${pathData(path)}`).not.toBeNull();
      return {
        from: Number(match?.[1]),
        startY: Number(match?.[2]),
        controlX: Number(match?.[3]),
        controlY: Number(match?.[4]),
        to: Number(match?.[5]),
        endY: Number(match?.[6]),
      };
    });
    expect(hops).toHaveLength(3);
    expect(hops.map(({ from, to }) => to - from)).toEqual([24, 24, 24]);
    expect(hops.map(({ from, to }) => [from, to])).toEqual([
      [24, 48],
      [48, 72],
      [72, 96],
    ]);
    expect(hops.map(({ startY, endY }) => [startY, endY])).toEqual([
      [60, 60],
      [60, 60],
      [60, 60],
    ]);
    expect(hops.map(({ from, controlX }) => controlX - from)).toEqual([12, 12, 12]);
    expect(new Set(hops.map(({ controlY }) => controlY))).toEqual(new Set([34]));
  });
});
