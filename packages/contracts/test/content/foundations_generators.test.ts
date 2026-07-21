import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { GeneratorRegistry } from "../../src/index.js";

type Parameters = Record<string, boolean | number | number[] | string>;

interface FoundationFixture {
  name: string;
  generator_id: string;
  seed: number;
  parameters: Parameters;
  expected: Record<string, unknown>;
}

const CASES = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/foundations_generator_cases.json", import.meta.url),
    "utf8",
  ),
) as FoundationFixture[];

const BANDS: Readonly<Record<string, readonly Parameters[]>> = {
  counting_v1: [
    { count_min: 1, count_max: 5 },
    { count_min: 1, count_max: 10 },
    { count_min: 1, count_max: 20 },
  ],
  number_bonds_v1: [
    { whole_min: 2, whole_max: 5, show_part: "left" },
    { whole_min: 2, whole_max: 10, show_part: "right" },
    { whole_min: 5, whole_max: 20, show_part: "random" },
  ],
  ten_frame_v1: [
    { target_min: 0, target_max: 5, frame_count: 1 },
    { target_min: 0, target_max: 10, frame_count: 1 },
    { target_min: 0, target_max: 20, frame_count: 2 },
  ],
  base_ten_v1: [
    { value_min: 10, value_max: 49, max_place: "tens" },
    { value_min: 10, value_max: 99, max_place: "tens" },
    { value_min: 100, value_max: 999, max_place: "hundreds" },
  ],
  number_line_v1: [
    { axis_min: 0, axis_max: 10, step_min: 1, step_max: 3, direction: "forward" },
    { axis_min: 0, axis_max: 20, step_min: 1, step_max: 5, direction: "bidirectional" },
    { axis_min: -10, axis_max: 30, step_min: 1, step_max: 10, direction: "bidirectional" },
  ],
  basic_operations_v1: [
    { operators: "addition", operand_min: 0, operand_max: 10, allow_negative: false },
    { operators: "mixed", operand_min: 0, operand_max: 20, allow_negative: false },
    { operators: "mixed", operand_min: 0, operand_max: 100, allow_negative: false },
  ],
};

function create(generatorId: string) {
  const generator = new GeneratorRegistry().create(generatorId);
  expect(generator).not.toBeNull();
  return generator!;
}

function isFlatSerializable(value: unknown): boolean {
  if (typeof value === "boolean" || typeof value === "string") return true;
  if (typeof value === "number") return Number.isSafeInteger(value);
  return Array.isArray(value) && value.length <= 128 && value.every(Number.isSafeInteger);
}

describe("foundation generator parity fixtures", () => {
  it.each(CASES)("matches $name", (fixture) => {
    const generator = create(fixture.generator_id);
    expect(generator.validateParameters(fixture.parameters)).toEqual({ valid: true, issues: [] });
    expect(generator.generate({}, { generator_parameters: fixture.parameters }, fixture.seed)).toEqual(
      fixture.expected,
    );
  });
});

describe("all six foundation generators", () => {
  it("generates 18,000 independently checked flat states across all three bands", () => {
    for (const [generatorId, bands] of Object.entries(BANDS)) {
      const generator = create(generatorId);
      for (const parameters of bands) {
        expect(generator.validateParameters(parameters)).toEqual({ valid: true, issues: [] });
        for (let seed = 1; seed <= 1_000; seed += 1) {
          const generated = generator.generate({}, { generator_parameters: parameters }, seed);
          expect(generated, `${generatorId} seed ${seed}`).not.toBeNull();
          const resolved = generated!.resolved_parameters;
          expect(Object.values(resolved).every(isFlatSerializable)).toBe(true);
          const answer = generated!.correct_answer;
          expect(answer.kind).toBe("integer");
          if (answer.kind !== "integer") continue;

          if (generatorId === "counting_v1") {
            const count = resolved.count as number;
            expect(resolved.manipulative_id).toBe("counters");
            expect(resolved.item_ids).toEqual(Array.from({ length: count }, (_value, index) => index));
            expect(resolved.initial_occupied).toEqual(resolved.item_ids);
            expect(answer.value).toBe(count);
          } else if (generatorId === "number_bonds_v1") {
            const parts = resolved.parts as number[];
            expect(resolved.manipulative_id).toBe("counters");
            expect(parts[0]! + parts[1]!).toBe(resolved.whole);
            expect((resolved.initial_occupied as number[]).length).toBe(resolved.shown_part);
            expect(answer.value).toBe(resolved.missing_part);
          } else if (generatorId === "ten_frame_v1") {
            const cells = resolved.occupied_cells as number[];
            expect(resolved.manipulative_id).toBe("ten_frame");
            expect(cells).toEqual(Array.from({ length: resolved.target as number }, (_value, index) => index));
            expect(cells.length).toBe(resolved.target);
            expect(cells.every((cell) => cell < (resolved.frame_count as number) * 10)).toBe(true);
            expect(answer.value).toBe(resolved.target);
          } else if (generatorId === "base_ten_v1") {
            expect(resolved.manipulative_id).toBe("base_ten");
            const reconstructed =
              (resolved.hundreds as number) * 100 +
              (resolved.tens as number) * 10 +
              (resolved.ones as number);
            expect(reconstructed).toBe(resolved.value);
            expect(resolved.place_counts).toEqual([
              resolved.hundreds,
              resolved.tens,
              resolved.ones,
            ]);
            expect(answer.value).toBe(resolved.value);
          } else if (generatorId === "number_line_v1") {
            expect(resolved.manipulative_id).toBe("number_line");
            const summedSteps = (resolved.signed_steps as number[]).reduce((sum, step) => sum + step, 0);
            expect((resolved.start as number) + summedSteps).toBe(resolved.endpoint);
            expect(resolved.endpoint as number).toBeGreaterThanOrEqual(resolved.axis_min as number);
            expect(resolved.endpoint as number).toBeLessThanOrEqual(resolved.axis_max as number);
            expect(resolved.visited_ticks).toEqual([resolved.start]);
            expect(answer.value).toBe(resolved.endpoint);
          } else {
            const operands = resolved.operands as number[];
            const recomputed =
              resolved.operator === "+" ? operands[0]! + operands[1]! : operands[0]! - operands[1]!;
            expect(resolved.manipulative_id).toBe("counters");
            expect(recomputed).toBe(resolved.answer);
            expect(recomputed).toBeGreaterThanOrEqual(0);
            expect(recomputed).toBeLessThanOrEqual(parameters.operand_max as number);
            expect(resolved.initial_counts).toEqual(operands);
            expect(answer.value).toBe(recomputed);
          }
        }
      }
    }
  }, 30_000);

  it("fails closed for malformed, physically impossible, and oversized contracts", () => {
    const invalidCases: readonly [string, Parameters][] = [
      ["counting_v1", { count_min: 0, count_max: 129 }],
      ["number_bonds_v1", { whole_min: 2, whole_max: 129, show_part: "middle" }],
      ["ten_frame_v1", { target_min: 0, target_max: 11, frame_count: 1 }],
      ["base_ten_v1", { value_min: 10, value_max: 100, max_place: "tens" }],
      ["number_line_v1", { axis_min: 0, axis_max: 128, step_min: 1, step_max: 129, direction: "sideways" }],
      ["basic_operations_v1", { operators: "addition", operand_min: 6, operand_max: 10, allow_negative: true }],
    ];
    for (const [generatorId, parameters] of invalidCases) {
      const generator = create(generatorId);
      expect(generator.validateParameters(parameters).valid).toBe(false);
      expect(() => generator.generate({}, { generator_parameters: parameters }, 1)).not.toThrow();
      expect(generator.generate({}, { generator_parameters: parameters }, 1)).toBeNull();
      expect(generator.lastError).toBe("INVALID_PARAMETERS");
    }
  });

  it("rejects non-uint32 seeds consistently", () => {
    for (const [generatorId, bands] of Object.entries(BANDS)) {
      const generator = create(generatorId);
      expect(generator.generate({}, { generator_parameters: bands[0]! }, 0x1_0000_0000)).toBeNull();
      expect(generator.lastError).toBe("INVALID_SEED");
    }
  });
});
