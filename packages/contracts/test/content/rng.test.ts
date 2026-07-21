import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { GENERATOR_IDS, GeneratorRegistry, SeededRng } from "../../src/index.js";

interface RngFixture {
  seed: number;
  zero_seed_normalization: number;
  values: number[];
  inclusive_ranges_2_5: number[];
  weighted_indices_1_3_2: number[];
}

const FIXTURE = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/rng_vectors.json", import.meta.url),
    "utf8",
  ),
) as RngFixture;

describe("xorshift32 content RNG", () => {
  it("matches the shared unsigned vector", () => {
    const rng = new SeededRng(FIXTURE.seed);
    expect(FIXTURE.values.map(() => rng.nextU32())).toEqual(FIXTURE.values);
  });

  it("normalizes zero and keeps inclusive ranges deterministic", () => {
    expect(new SeededRng(0).state).toBe(FIXTURE.zero_seed_normalization);
    const rng = new SeededRng(FIXTURE.seed);
    expect(FIXTURE.inclusive_ranges_2_5.map(() => rng.rangeInt(2, 5))).toEqual(
      FIXTURE.inclusive_ranges_2_5,
    );
    expect(() => rng.rangeInt(5, 2)).toThrow(RangeError);
  });

  it("uses deterministic integer weighted picks and rejects invalid weights", () => {
    const rng = new SeededRng(FIXTURE.seed);
    expect(FIXTURE.weighted_indices_1_3_2.map(() => rng.weightedIndex([1, 3, 2]))).toEqual(
      FIXTURE.weighted_indices_1_3_2,
    );
    expect(rng.weightedIndex([])).toBe(-1);
    expect(rng.weightedIndex([1, 0, 2])).toBe(-1);
    expect(rng.weightedIndex([1, 1.5])).toBe(-1);
  });
});

describe("generator registry contract", () => {
  it("is a literal allowlist of all and only published generator IDs", () => {
    const registry = new GeneratorRegistry();
    expect(GENERATOR_IDS.every((id) => registry.create(id) !== null)).toBe(true);
    expect(registry.create("remote_javascript")).toBeNull();
  });
});
