import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { GeneratorRegistry } from "../../src/index.js";

interface ArithmeticFixture {
  name: string;
  generator_id: string;
  seed: number;
  parameters: Record<string, boolean | number | string>;
  expected: {
    operands: number[];
    operator: string;
    carry?: boolean;
    borrow?: boolean;
    display_mode: string;
    answer: number;
  };
}

const CASES = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/arithmetic_generator_cases.json", import.meta.url),
    "utf8",
  ),
) as ArithmeticFixture[];

function generate(generatorId: string, parameters: ArithmeticFixture["parameters"], seed: number) {
  const generator = new GeneratorRegistry().create(generatorId);
  expect(generator).not.toBeNull();
  expect(generator!.validateParameters(parameters)).toEqual({ valid: true, issues: [] });
  return generator!.generate({}, { generator_parameters: parameters }, seed);
}

function additionCarries(operands: readonly number[], onesOnly: boolean): boolean {
  let values = [...operands];
  do {
    if (values.reduce((sum, value) => sum + (value % 10), 0) >= 10) return true;
    values = values.map((value) => Math.floor(value / 10));
  } while (!onesOnly && values.some((value) => value > 0));
  return false;
}

function subtractionBorrows(minuend: number, subtrahend: number, onesOnly: boolean): boolean {
  let left = minuend;
  let right = subtrahend;
  let borrowed = 0;
  do {
    const available = (left % 10) - borrowed;
    const needed = right % 10;
    if (available < needed) return true;
    borrowed = 0;
    left = Math.floor(left / 10);
    right = Math.floor(right / 10);
  } while (!onesOnly && (left > 0 || right > 0));
  return false;
}

describe("arithmetic generator parity fixtures", () => {
  it.each(CASES)("matches $name", (fixture) => {
    const generated = generate(fixture.generator_id, fixture.parameters, fixture.seed);
    expect(generated?.resolved_parameters).toEqual(fixture.expected);
    expect(generated?.correct_answer).toEqual({ kind: "integer", value: fixture.expected.answer });
    expect(generated?.prompt.key).toBe(`question.${fixture.generator_id.replace("_v1", "")}`);
  });
});

describe("arithmetic generator properties", () => {
  const additionCases = [
    { operand_count: 2, operand_min: 0, operand_max: 99, place_mode: "full", carry: "allow" },
    { operand_count: 2, operand_min: 0, operand_max: 9, place_mode: "ones_digit", carry: "forbid" },
    { operand_count: 3, operand_min: 0, operand_max: 9, place_mode: "ones_digit", carry: "require" },
  ] as const;

  it.each(additionCases)("keeps addition bounds and carry policy: $carry/$operand_count", (parameters) => {
    for (let seed = 1; seed <= 1_000; seed += 1) {
      const generated = generate("addition_v1", parameters, seed)!;
      const resolved = generated.resolved_parameters as unknown as ArithmeticFixture["expected"];
      expect(resolved.operands).toHaveLength(parameters.operand_count);
      expect(resolved.operands.every((value) => value >= parameters.operand_min && value <= parameters.operand_max)).toBe(true);
      expect(resolved.answer).toBe(resolved.operands.reduce((sum, value) => sum + value, 0));
      const carries = additionCarries(resolved.operands, parameters.place_mode === "ones_digit");
      expect(resolved.carry).toBe(carries);
      if (parameters.carry !== "allow") expect(carries).toBe(parameters.carry === "require");
    }
  });

  const subtractionCases = [
    { operand_count: 3, operand_min: 0, operand_max: 99, place_mode: "full", borrow: "allow", allow_negative: false },
    { operand_count: 2, operand_min: 0, operand_max: 19, place_mode: "ones_digit", borrow: "forbid", allow_negative: false },
    { operand_count: 2, operand_min: 0, operand_max: 99, place_mode: "full", borrow: "require", allow_negative: false },
  ] as const;

  it.each(subtractionCases)("keeps subtraction nonnegative and borrow policy: $borrow", (parameters) => {
    for (let seed = 1; seed <= 1_000; seed += 1) {
      const generated = generate("subtraction_v1", parameters, seed)!;
      const resolved = generated.resolved_parameters as unknown as ArithmeticFixture["expected"];
      const [left, ...rest] = resolved.operands;
      expect(resolved.operands).toHaveLength(parameters.operand_count);
      expect(
        resolved.operands.every(
          (value) => value >= parameters.operand_min && value <= parameters.operand_max,
        ),
      ).toBe(true);
      const subtrahend = rest.reduce((sum, value) => sum + value, 0);
      expect(resolved.answer).toBe(left! - subtrahend);
      expect(resolved.answer).toBeGreaterThanOrEqual(0);
      const borrows = subtractionBorrows(
        left!,
        subtrahend,
        parameters.place_mode === "ones_digit",
      );
      expect(resolved.borrow).toBe(borrows);
      if (parameters.borrow !== "allow") expect(borrows).toBe(parameters.borrow === "require");
    }
  });

  it("keeps multiplication bounds and recomputes every answer", () => {
    const parameters = { left_min: 2, left_max: 12, right_min: 2, right_max: 9, display: "column" };
    for (let seed = 1; seed <= 1_000; seed += 1) {
      const generated = generate("multiplication_v1", parameters, seed)!;
      const resolved = generated.resolved_parameters as unknown as ArithmeticFixture["expected"];
      expect(resolved.answer).toBe(resolved.operands[0]! * resolved.operands[1]!);
      expect(resolved.operands[0]).toBeGreaterThanOrEqual(2);
      expect(resolved.operands[0]).toBeLessThanOrEqual(12);
      expect(resolved.operands[1]).toBeGreaterThanOrEqual(2);
      expect(resolved.operands[1]).toBeLessThanOrEqual(9);
    }
  });

  it("rejects invalid and unsatisfiable authored constraints without relaxing them", () => {
    const addition = new GeneratorRegistry().create("addition_v1")!;
    expect(addition.validateParameters({ operand_count: 4 })).toMatchObject({ valid: false });
    expect(
      addition.generate(
        {},
        { generator_parameters: { operand_count: 2, operand_min: 0, operand_max: 4, place_mode: "ones_digit", carry: "require" } },
        1,
      ),
    ).toBeNull();
    expect(addition.lastError).toBe("UNSATISFIABLE_PARAMETERS");

    const subtraction = new GeneratorRegistry().create("subtraction_v1")!;
    expect(
      subtraction.validateParameters({
        operand_count: 2,
        operand_min: 0,
        operand_max: 9,
        place_mode: "ones_digit",
        borrow: "allow",
        allow_negative: true,
      }),
    ).toMatchObject({ valid: false });
  });

  it("rejects every sampled range wider than one uint32 draw before generation", () => {
    const addition = new GeneratorRegistry().create("addition_v1")!;
    const hugeAddition = {
      operand_count: 2,
      operand_min: 0,
      operand_max: 0x1_0000_0000,
      place_mode: "full",
      carry: "allow",
    };
    expect(addition.validateParameters(hugeAddition).issues).toContain("OPERAND_RANGE_WIDTH");
    expect(() => addition.generate({}, { generator_parameters: hugeAddition }, 1)).not.toThrow();
    expect(addition.generate({}, { generator_parameters: hugeAddition }, 1)).toBeNull();
    expect(addition.lastError).toBe("INVALID_PARAMETERS");

    const subtraction = new GeneratorRegistry().create("subtraction_v1")!;
    const hugeSubtraction = {
      operand_count: 2,
      operand_min: 1,
      operand_max: 0x1_0000_0001,
      place_mode: "full",
      borrow: "allow",
      allow_negative: false,
    };
    expect(subtraction.validateParameters(hugeSubtraction).issues).toContain("OPERAND_RANGE_WIDTH");
    expect(() => subtraction.generate({}, { generator_parameters: hugeSubtraction }, 1)).not.toThrow();
    expect(subtraction.generate({}, { generator_parameters: hugeSubtraction }, 1)).toBeNull();

    const multiplication = new GeneratorRegistry().create("multiplication_v1")!;
    const hugeLeft = {
      left_min: 0,
      left_max: 0x1_0000_0000,
      right_min: 0,
      right_max: 0,
      display: "horizontal",
    };
    expect(multiplication.validateParameters(hugeLeft).issues).toContain("LEFT_RANGE_WIDTH");
    expect(() => multiplication.generate({}, { generator_parameters: hugeLeft }, 1)).not.toThrow();
    expect(multiplication.generate({}, { generator_parameters: hugeLeft }, 1)).toBeNull();

    const hugeRight = { ...hugeLeft, left_max: 0, right_max: 0x1_0000_0000 };
    expect(multiplication.validateParameters(hugeRight).issues).toContain("RIGHT_RANGE_WIDTH");
  });

  it("rejects generator seeds outside the unsigned 32-bit contract without throwing", () => {
    const generator = new GeneratorRegistry().create("addition_v1")!;
    const parameters = {
      operand_count: 2,
      operand_min: 0,
      operand_max: 9,
      place_mode: "ones_digit",
      carry: "allow",
    };
    expect(() =>
      generator.generate({}, { generator_parameters: parameters }, 0x1_0000_0000),
    ).not.toThrow();
    expect(generator.generate({}, { generator_parameters: parameters }, 0x1_0000_0000)).toBeNull();
    expect(generator.lastError).toBe("INVALID_SEED");
  });
});
