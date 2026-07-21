import type { GeneratorId } from "../ids.js";
import type { ResolvedParametersV1 } from "../types.js";
import { isSupportedRngRange, isUint32, SeededRng } from "./rng.js";
import type {
  GeneratedQuestionFields,
  GeneratorValidationResult,
  QuestionGeneratorContract,
} from "./types.js";

const MAX_ATTEMPTS = 128;
const SAFE_INTEGER_MAX = Number.MAX_SAFE_INTEGER;
const PLACE_MODES = new Set(["full", "ones_digit"]);
const POLICIES = new Set(["allow", "forbid", "require"]);
const DISPLAYS = new Set(["horizontal", "column"]);

type Parameters = Readonly<Record<string, unknown>>;

function hasExactKeys(parameters: Parameters, expected: readonly string[]): boolean {
  const actual = Object.keys(parameters).sort();
  return actual.length === expected.length && [...expected].sort().every((key, index) => key === actual[index]);
}

function isNonnegativeSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function report(issues: string[]): GeneratorValidationResult {
  return { valid: issues.length === 0, issues };
}

function additionCarries(operands: readonly number[], onesOnly: boolean): boolean {
  let values = [...operands];
  while (true) {
    if (values.reduce((sum, value) => sum + (value % 10), 0) >= 10) return true;
    values = values.map((value) => Math.floor(value / 10));
    if (onesOnly || values.every((value) => value === 0)) return false;
  }
}

function subtractionBorrows(minuend: number, subtrahend: number, onesOnly: boolean): boolean {
  let left = minuend;
  let right = subtrahend;
  while (true) {
    if (left % 10 < right % 10) return true;
    if (onesOnly) return false;
    left = Math.floor(left / 10);
    right = Math.floor(right / 10);
    if (left === 0 && right === 0) return false;
  }
}

function policyAccepts(policy: unknown, condition: boolean): boolean {
  return policy === "allow" || (policy === "require" ? condition : !condition);
}

abstract class ArithmeticGenerator implements QuestionGeneratorContract {
  abstract readonly generatorId: GeneratorId;
  lastError = "";

  abstract validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult;
  abstract generate(
    activity: Readonly<Record<string, unknown>>,
    band: Readonly<Record<string, unknown>>,
    seed: number,
  ): GeneratedQuestionFields | null;

  protected parameters(band: Readonly<Record<string, unknown>>): Parameters | null {
    const value = band.generator_parameters;
    return value !== null && typeof value === "object" && !Array.isArray(value)
      ? (value as Parameters)
      : null;
  }

  protected invalid(): null {
    this.lastError = "INVALID_PARAMETERS";
    return null;
  }

  protected unsatisfiable(): null {
    this.lastError = "UNSATISFIABLE_PARAMETERS";
    return null;
  }

  protected rng(seed: number): SeededRng | null {
    if (!isUint32(seed)) {
      this.lastError = "INVALID_SEED";
      return null;
    }
    return new SeededRng(seed);
  }

  protected fields(
    promptKey: string,
    operands: number[],
    resolvedParameters: ResolvedParametersV1,
    answer: number,
  ): GeneratedQuestionFields {
    this.lastError = "";
    return {
      resolved_parameters: resolvedParameters,
      prompt: { key: promptKey, args: { expression: operands.join(" ") } },
      correct_answer: { kind: "integer", value: answer },
    };
  }
}

export class AdditionGenerator extends ArithmeticGenerator {
  readonly generatorId = "addition_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["operand_count", "operand_min", "operand_max", "place_mode", "carry"])) issues.push("PARAMETER_KEYS");
    if (values.operand_count !== 2 && values.operand_count !== 3) issues.push("OPERAND_COUNT");
    if (!isNonnegativeSafeInteger(values.operand_min) || !isNonnegativeSafeInteger(values.operand_max) || (values.operand_max as number) < (values.operand_min as number)) issues.push("OPERAND_RANGE");
    if (!PLACE_MODES.has(values.place_mode as string)) issues.push("PLACE_MODE");
    if (!POLICIES.has(values.carry as string)) issues.push("CARRY_POLICY");
    if (
      isNonnegativeSafeInteger(values.operand_min) &&
      isNonnegativeSafeInteger(values.operand_max) &&
      values.operand_max >= values.operand_min &&
      !isSupportedRngRange(values.operand_min, values.operand_max)
    ) {
      issues.push("OPERAND_RANGE_WIDTH");
    }
    if (
      isNonnegativeSafeInteger(values.operand_max) &&
      (values.operand_count === 2 || values.operand_count === 3) &&
      values.operand_max > Math.floor(SAFE_INTEGER_MAX / values.operand_count)
    ) {
      issues.push("OVERFLOW_RANGE");
    }
    return report(issues);
  }

  generate(
    _activity: Readonly<Record<string, unknown>>,
    band: Readonly<Record<string, unknown>>,
    seed: number,
  ): GeneratedQuestionFields | null {
    const parameters = this.parameters(band);
    if (parameters === null || !this.validateParameters(parameters as ResolvedParametersV1).valid) return this.invalid();
    const rng = this.rng(seed);
    if (rng === null) return null;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
      const operands = Array.from({ length: parameters.operand_count as number }, () =>
        rng.rangeInt(parameters.operand_min as number, parameters.operand_max as number),
      );
      const carry = additionCarries(operands, parameters.place_mode === "ones_digit");
      if (!policyAccepts(parameters.carry, carry)) continue;
      const answer = operands.reduce((sum, value) => sum + value, 0);
      return this.fields(
        "question.addition",
        operands,
        { operands, operator: "+", carry, display_mode: parameters.place_mode as string, answer },
        answer,
      );
    }
    return this.unsatisfiable();
  }
}

export class SubtractionGenerator extends ArithmeticGenerator {
  readonly generatorId = "subtraction_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["operand_count", "operand_min", "operand_max", "place_mode", "borrow", "allow_negative"])) issues.push("PARAMETER_KEYS");
    if (values.operand_count !== 2 && values.operand_count !== 3) issues.push("OPERAND_COUNT");
    if (!isNonnegativeSafeInteger(values.operand_min) || !isNonnegativeSafeInteger(values.operand_max) || (values.operand_max as number) < (values.operand_min as number)) issues.push("OPERAND_RANGE");
    if (!PLACE_MODES.has(values.place_mode as string)) issues.push("PLACE_MODE");
    if (!POLICIES.has(values.borrow as string)) issues.push("BORROW_POLICY");
    if (values.allow_negative !== false) issues.push("ALLOW_NEGATIVE");
    if (
      isNonnegativeSafeInteger(values.operand_min) &&
      isNonnegativeSafeInteger(values.operand_max) &&
      values.operand_max >= values.operand_min &&
      !isSupportedRngRange(values.operand_min, values.operand_max)
    ) {
      issues.push("OPERAND_RANGE_WIDTH");
    }
    if (
      isNonnegativeSafeInteger(values.operand_max) &&
      (values.operand_count === 2 || values.operand_count === 3) &&
      values.operand_max > Math.floor(SAFE_INTEGER_MAX / values.operand_count)
    ) {
      issues.push("OVERFLOW_RANGE");
    }
    return report(issues);
  }

  generate(
    _activity: Readonly<Record<string, unknown>>,
    band: Readonly<Record<string, unknown>>,
    seed: number,
  ): GeneratedQuestionFields | null {
    const parameters = this.parameters(band);
    if (parameters === null || !this.validateParameters(parameters as ResolvedParametersV1).valid) return this.invalid();
    const rng = this.rng(seed);
    if (rng === null) return null;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
      const operands = Array.from({ length: parameters.operand_count as number }, () =>
        rng.rangeInt(parameters.operand_min as number, parameters.operand_max as number),
      );
      const subtrahend = operands.slice(1).reduce((sum, value) => sum + value, 0);
      const answer = operands[0]! - subtrahend;
      if (answer < 0) continue;
      const borrow = subtractionBorrows(
        operands[0]!,
        subtrahend,
        parameters.place_mode === "ones_digit",
      );
      if (!policyAccepts(parameters.borrow, borrow)) continue;
      return this.fields(
        "question.subtraction",
        operands,
        { operands, operator: "-", borrow, display_mode: parameters.place_mode as string, answer },
        answer,
      );
    }
    return this.unsatisfiable();
  }
}

export class MultiplicationGenerator extends ArithmeticGenerator {
  readonly generatorId = "multiplication_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["left_min", "left_max", "right_min", "right_max", "display"])) issues.push("PARAMETER_KEYS");
    if (!isNonnegativeSafeInteger(values.left_min) || !isNonnegativeSafeInteger(values.left_max) || (values.left_max as number) < (values.left_min as number)) issues.push("LEFT_RANGE");
    if (!isNonnegativeSafeInteger(values.right_min) || !isNonnegativeSafeInteger(values.right_max) || (values.right_max as number) < (values.right_min as number)) issues.push("RIGHT_RANGE");
    if (!DISPLAYS.has(values.display as string)) issues.push("DISPLAY");
    if (
      isNonnegativeSafeInteger(values.left_min) &&
      isNonnegativeSafeInteger(values.left_max) &&
      values.left_max >= values.left_min &&
      !isSupportedRngRange(values.left_min, values.left_max)
    ) {
      issues.push("LEFT_RANGE_WIDTH");
    }
    if (
      isNonnegativeSafeInteger(values.right_min) &&
      isNonnegativeSafeInteger(values.right_max) &&
      values.right_max >= values.right_min &&
      !isSupportedRngRange(values.right_min, values.right_max)
    ) {
      issues.push("RIGHT_RANGE_WIDTH");
    }
    if (
      isNonnegativeSafeInteger(values.left_max) &&
      isNonnegativeSafeInteger(values.right_max) &&
      values.left_max !== 0 &&
      values.right_max > Math.floor(SAFE_INTEGER_MAX / values.left_max)
    ) {
      issues.push("OVERFLOW_RANGE");
    }
    return report(issues);
  }

  generate(
    _activity: Readonly<Record<string, unknown>>,
    band: Readonly<Record<string, unknown>>,
    seed: number,
  ): GeneratedQuestionFields | null {
    const parameters = this.parameters(band);
    if (parameters === null || !this.validateParameters(parameters as ResolvedParametersV1).valid) return this.invalid();
    const rng = this.rng(seed);
    if (rng === null) return null;
    const operands = [
      rng.rangeInt(parameters.left_min as number, parameters.left_max as number),
      rng.rangeInt(parameters.right_min as number, parameters.right_max as number),
    ];
    const answer = operands[0]! * operands[1]!;
    return this.fields(
      "question.multiplication",
      operands,
      { operands, operator: "*", display_mode: parameters.display as string, answer },
      answer,
    );
  }
}
