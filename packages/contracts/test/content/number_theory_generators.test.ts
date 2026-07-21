import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { GeneratorRegistry } from "../../src/index.js";

interface NumberTheoryFixture {
  name: string;
  generator_id: string;
  seed: number;
  parameters: Record<string, boolean | number | number[]>;
  expected: {
    resolved_parameters: Record<string, boolean | number | number[] | string>;
    prompt: { key: string; args: Record<string, number | string> };
    correct_answer:
      | { kind: "integer"; value: number }
      | { kind: "integer_list"; values: number[]; order_matters: boolean };
  };
}

const CASES = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/number_theory_generator_cases.json", import.meta.url),
    "utf8",
  ),
) as NumberTheoryFixture[];

function create(generatorId: string) {
  const generator = new GeneratorRegistry().create(generatorId);
  expect(generator).not.toBeNull();
  return generator!;
}

function gcd(left: number, right: number): number {
  let a = left;
  let b = right;
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}

function lcm(operands: readonly number[]): number {
  return operands.reduce((answer, operand) => (answer / gcd(answer, operand)) * operand, 1);
}

describe("number theory generator parity fixtures", () => {
  it.each(CASES)("matches $name", (fixture) => {
    const generator = create(fixture.generator_id);
    expect(generator.validateParameters(fixture.parameters)).toEqual({ valid: true, issues: [] });
    const generated = generator.generate(
      {},
      { generator_parameters: fixture.parameters },
      fixture.seed,
    );
    expect(generated).toEqual(fixture.expected);
  });
});

describe("common multiple generator", () => {
  it("keeps all operand constraints and recomputes an exact safe LCM for 1000 seeds", () => {
    const parameters = {
      operand_count: 3,
      operand_min: 2,
      operand_max: 30,
      require_distinct: true,
    };
    const generator = create("common_multiple_v1");
    for (let seed = 1; seed <= 1_000; seed += 1) {
      const generated = generator.generate({}, { generator_parameters: parameters }, seed)!;
      expect(generated).not.toBeNull();
      const resolved = generated.resolved_parameters as {
        operands: number[];
        operator: string;
        answer: number;
      };
      expect(resolved.operands).toHaveLength(parameters.operand_count);
      expect(new Set(resolved.operands).size).toBe(parameters.operand_count);
      expect(
        resolved.operands.every(
          (operand) => operand >= parameters.operand_min && operand <= parameters.operand_max,
        ),
      ).toBe(true);
      expect(resolved.operator).toBe("lcm");
      expect(resolved.answer).toBe(lcm(resolved.operands));
      expect(Number.isSafeInteger(resolved.answer)).toBe(true);
      expect(generated.correct_answer).toEqual({ kind: "integer", value: resolved.answer });
    }
  });

  it("rejects malformed parameters and fails closed after unsatisfiable rejections", () => {
    const generator = create("common_multiple_v1");
    expect(
      generator.validateParameters({
        operand_count: 4,
        operand_min: 0,
        operand_max: Number.MAX_SAFE_INTEGER,
        require_distinct: "yes",
      }),
    ).toMatchObject({ valid: false });
    expect(
      generator.generate(
        {},
        {
          generator_parameters: {
            operand_count: 3,
            operand_min: 2,
            operand_max: 3,
            require_distinct: true,
          },
        },
        1,
      ),
    ).toBeNull();
    expect(generator.lastError).toBe("UNSATISFIABLE_PARAMETERS");
  });
});

describe("prime factorization generator", () => {
  it("uses only authored primes, preserves repeated slots, and recomputes values for 1000 seeds", () => {
    const parameters = {
      value_min: 4,
      value_max: 20_000,
      factor_count_min: 2,
      factor_count_max: 5,
      allowed_primes: [2, 3, 5, 7],
    };
    const generator = create("prime_factorization_v1");
    for (let seed = 1; seed <= 1_000; seed += 1) {
      const generated = generator.generate({}, { generator_parameters: parameters }, seed)!;
      expect(generated).not.toBeNull();
      const resolved = generated.resolved_parameters as {
        value: number;
        factors: number[];
        factor_count: number;
        allowed_primes: number[];
      };
      expect(resolved.value).toBeGreaterThanOrEqual(parameters.value_min);
      expect(resolved.value).toBeLessThanOrEqual(parameters.value_max);
      expect(Number.isSafeInteger(resolved.value)).toBe(true);
      expect(resolved.factors).toHaveLength(resolved.factor_count);
      expect(resolved.factor_count).toBeGreaterThanOrEqual(parameters.factor_count_min);
      expect(resolved.factor_count).toBeLessThanOrEqual(parameters.factor_count_max);
      expect(resolved.factors.every((factor) => parameters.allowed_primes.includes(factor))).toBe(true);
      expect(resolved.factors).toEqual([...resolved.factors].sort((a, b) => a - b));
      expect(resolved.value).toBe(resolved.factors.reduce((product, factor) => product * factor, 1));
      expect(resolved.allowed_primes).toEqual(parameters.allowed_primes);
      expect(generated.correct_answer).toEqual({
        kind: "integer_list",
        values: resolved.factors,
        order_matters: false,
      });
    }
  });

  it("rejects non-prime, duplicate, unsafe, and impossible authored parameters", () => {
    const generator = create("prime_factorization_v1");
    expect(
      generator.validateParameters({
        value_min: 2,
        value_max: Number.MAX_SAFE_INTEGER + 1,
        factor_count_min: 1,
        factor_count_max: 2,
        allowed_primes: [2, 4, 2],
      }),
    ).toMatchObject({ valid: false });

    expect(
      generator.generate(
        {},
        {
          generator_parameters: {
            value_min: 17,
            value_max: 17,
            factor_count_min: 2,
            factor_count_max: 2,
            allowed_primes: [2, 3],
          },
        },
        1,
      ),
    ).toBeNull();
    expect(generator.lastError).toBe("UNSATISFIABLE_PARAMETERS");
  });
});
