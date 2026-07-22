import type { GeneratorId } from "../ids.js";
import type { ResolvedParametersV1 } from "../types.js";
import { isSupportedRngRange, isUint32, SeededRng } from "./rng.js";
import type {
  GeneratedQuestionFields,
  GeneratorValidationResult,
  QuestionGeneratorContract,
} from "./types.js";

const MAX_STATE_ITEMS = 128;
const MAX_BASIC_RESULT = 100;
const SHOW_PART_MODES = new Set(["left", "right", "random"]);
const MAX_PLACE_VALUES = new Map([
  ["ones", 9],
  ["tens", 99],
  ["hundreds", 999],
]);
const DIRECTIONS = new Set(["forward", "backward", "bidirectional"]);
const OPERATOR_MODES = new Set(["addition", "subtraction", "mixed"]);

type Parameters = Readonly<Record<string, unknown>>;

function hasExactKeys(parameters: Parameters, expected: readonly string[]): boolean {
  const actual = Object.keys(parameters).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length && actual.every((key, index) => key === sortedExpected[index]);
}

function isSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value);
}

function isNonnegativeSafeInteger(value: unknown): value is number {
  return isSafeInteger(value) && value >= 0;
}

function isPositiveSafeInteger(value: unknown): value is number {
  return isSafeInteger(value) && value >= 1;
}

function report(issues: string[]): GeneratorValidationResult {
  return { valid: issues.length === 0, issues };
}

function indices(count: number): number[] {
  return Array.from({ length: count }, (_value, index) => index);
}

abstract class FoundationGenerator implements QuestionGeneratorContract {
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

  protected rng(seed: number): SeededRng | null {
    if (!isUint32(seed)) {
      this.lastError = "INVALID_SEED";
      return null;
    }
    return new SeededRng(seed);
  }

  protected invalid(): null {
    this.lastError = "INVALID_PARAMETERS";
    return null;
  }

  protected fields(
    resolvedParameters: ResolvedParametersV1,
    promptKey: string,
    promptArgs: Record<string, number | string>,
    answer: number,
  ): GeneratedQuestionFields {
    this.lastError = "";
    return {
      resolved_parameters: resolvedParameters,
      prompt: { key: promptKey, args: promptArgs },
      correct_answer: { kind: "integer", value: answer },
    };
  }
}

export class CountingGenerator extends FoundationGenerator {
  readonly generatorId = "counting_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["count_min", "count_max"])) issues.push("PARAMETER_KEYS");
    if (
      !isPositiveSafeInteger(values.count_min) ||
      !isPositiveSafeInteger(values.count_max) ||
      values.count_max < values.count_min ||
      values.count_max > MAX_STATE_ITEMS
    ) {
      issues.push("COUNT_RANGE");
    } else if (!isSupportedRngRange(values.count_min, values.count_max)) {
      issues.push("COUNT_RANGE_WIDTH");
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
    const count = rng.rangeInt(parameters.count_min as number, parameters.count_max as number);
    const itemIds = indices(count);
    return this.fields(
      {
        count,
        item_ids: itemIds,
        manipulative_id: "counters",
        initial_occupied: [...itemIds],
      },
      "question.counting",
      {},
      count,
    );
  }
}

export class NumberBondsGenerator extends FoundationGenerator {
  readonly generatorId = "number_bonds_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["whole_min", "whole_max", "show_part"])) issues.push("PARAMETER_KEYS");
    if (
      !isPositiveSafeInteger(values.whole_min) ||
      !isPositiveSafeInteger(values.whole_max) ||
      values.whole_min < 2 ||
      values.whole_max < values.whole_min ||
      values.whole_max > MAX_STATE_ITEMS
    ) {
      issues.push("WHOLE_RANGE");
    } else if (!isSupportedRngRange(values.whole_min, values.whole_max)) {
      issues.push("WHOLE_RANGE_WIDTH");
    }
    if (!SHOW_PART_MODES.has(values.show_part as string)) issues.push("SHOW_PART");
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
    const whole = rng.rangeInt(parameters.whole_min as number, parameters.whole_max as number);
    const leftPart = rng.rangeInt(0, whole);
    const rightPart = whole - leftPart;
    const shownSide = parameters.show_part === "random"
      ? (rng.rangeInt(0, 1) === 0 ? "left" : "right")
      : (parameters.show_part as string);
    const shownPart = shownSide === "left" ? leftPart : rightPart;
    const missingPart = shownSide === "left" ? rightPart : leftPart;
    return this.fields(
      {
        whole,
        parts: [leftPart, rightPart],
        shown_side: shownSide,
        shown_part: shownPart,
        missing_part: missingPart,
        manipulative_id: "counters",
        initial_occupied: indices(shownPart),
      },
      "question.number_bonds",
      { whole, shown_part: shownPart },
      missingPart,
    );
  }
}

export class TenFrameGenerator extends FoundationGenerator {
  readonly generatorId = "ten_frame_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["target_min", "target_max", "frame_count"])) issues.push("PARAMETER_KEYS");
    if (values.frame_count !== 1 && values.frame_count !== 2) issues.push("FRAME_COUNT");
    const capacity = values.frame_count === 1 || values.frame_count === 2 ? values.frame_count * 10 : -1;
    if (
      !isNonnegativeSafeInteger(values.target_min) ||
      !isNonnegativeSafeInteger(values.target_max) ||
      values.target_max < values.target_min ||
      values.target_max > capacity
    ) {
      issues.push("TARGET_RANGE");
    } else if (!isSupportedRngRange(values.target_min, values.target_max)) {
      issues.push("TARGET_RANGE_WIDTH");
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
    const target = rng.rangeInt(parameters.target_min as number, parameters.target_max as number);
    return this.fields(
      {
        target,
        frame_count: parameters.frame_count as number,
        occupied_cells: indices(target),
        manipulative_id: "ten_frame",
      },
      "question.ten_frame",
      {},
      target,
    );
  }
}

export class BaseTenGenerator extends FoundationGenerator {
  readonly generatorId = "base_ten_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["value_min", "value_max", "max_place"])) issues.push("PARAMETER_KEYS");
    const placeMaximum = MAX_PLACE_VALUES.get(values.max_place as string);
    if (placeMaximum === undefined) issues.push("MAX_PLACE");
    if (
      !isNonnegativeSafeInteger(values.value_min) ||
      !isNonnegativeSafeInteger(values.value_max) ||
      values.value_max < values.value_min ||
      placeMaximum === undefined ||
      values.value_max > placeMaximum
    ) {
      issues.push("VALUE_RANGE");
    } else if (!isSupportedRngRange(values.value_min, values.value_max)) {
      issues.push("VALUE_RANGE_WIDTH");
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
    const value = rng.rangeInt(parameters.value_min as number, parameters.value_max as number);
    const hundreds = Math.floor(value / 100);
    const tens = Math.floor(value / 10) % 10;
    const ones = value % 10;
    return this.fields(
      {
        value,
        hundreds,
        tens,
        ones,
        place_counts: [hundreds, tens, ones],
        manipulative_id: "base_ten",
      },
      "question.base_ten",
      {},
      value,
    );
  }
}

export class NumberLineGenerator extends FoundationGenerator {
  readonly generatorId = "number_line_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["axis_min", "axis_max", "step_min", "step_max", "direction"])) issues.push("PARAMETER_KEYS");
    const validAxis =
      isSafeInteger(values.axis_min) &&
      isSafeInteger(values.axis_max) &&
      values.axis_max > values.axis_min &&
      values.axis_max - values.axis_min <= MAX_STATE_ITEMS - 1;
    if (!validAxis) issues.push("AXIS_RANGE");
    if (
      !isPositiveSafeInteger(values.step_min) ||
      !isPositiveSafeInteger(values.step_max) ||
      values.step_max < values.step_min ||
      !validAxis ||
      values.step_max > (values.axis_max as number) - (values.axis_min as number)
    ) {
      issues.push("STEP_RANGE");
    } else if (!isSupportedRngRange(values.step_min, values.step_max)) {
      issues.push("STEP_RANGE_WIDTH");
    }
    if (!DIRECTIONS.has(values.direction as string)) issues.push("DIRECTION");
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
    const direction = parameters.direction === "bidirectional"
      ? (rng.rangeInt(0, 1) === 0 ? "forward" : "backward")
      : (parameters.direction as string);
    const stepMagnitude = rng.rangeInt(parameters.step_min as number, parameters.step_max as number);
    const forward = direction === "forward";
    const start = forward
      ? rng.rangeInt(parameters.axis_min as number, (parameters.axis_max as number) - stepMagnitude)
      : rng.rangeInt((parameters.axis_min as number) + stepMagnitude, parameters.axis_max as number);
    const signedStep = forward ? stepMagnitude : -stepMagnitude;
    const endpoint = start + signedStep;
    return this.fields(
      {
        axis_min: parameters.axis_min as number,
        axis_max: parameters.axis_max as number,
        start,
        signed_steps: [signedStep],
        endpoint,
        direction,
        visited_ticks: [start],
        manipulative_id: "number_line",
      },
      "question.number_line",
      { start, step: signedStep },
      endpoint,
    );
  }
}

export class BasicOperationsGenerator extends FoundationGenerator {
  readonly generatorId = "basic_operations_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["operators", "operand_min", "operand_max", "allow_negative"])) issues.push("PARAMETER_KEYS");
    if (!OPERATOR_MODES.has(values.operators as string)) issues.push("OPERATORS");
    if (
      !isNonnegativeSafeInteger(values.operand_min) ||
      !isNonnegativeSafeInteger(values.operand_max) ||
      values.operand_max < values.operand_min ||
      values.operand_max > MAX_BASIC_RESULT
    ) {
      issues.push("OPERAND_RANGE");
    } else if (!isSupportedRngRange(values.operand_min, values.operand_max)) {
      issues.push("OPERAND_RANGE_WIDTH");
    }
    if (values.allow_negative !== false) issues.push("ALLOW_NEGATIVE");
    if (
      (values.operators === "addition" || values.operators === "mixed") &&
      isNonnegativeSafeInteger(values.operand_min) &&
      isNonnegativeSafeInteger(values.operand_max) &&
      values.operand_min > Math.floor(values.operand_max / 2)
    ) {
      issues.push("ADDITION_RANGE");
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
    const operator = parameters.operators === "mixed"
      ? (rng.rangeInt(0, 1) === 0 ? "+" : "-")
      : (parameters.operators === "addition" ? "+" : "-");
    const minimum = parameters.operand_min as number;
    const maximum = parameters.operand_max as number;
    let left: number;
    let right: number;
    if (operator === "+") {
      left = rng.rangeInt(minimum, maximum - minimum);
      right = rng.rangeInt(minimum, maximum - left);
    } else {
      left = rng.rangeInt(minimum, maximum);
      right = rng.rangeInt(minimum, left);
    }
    const answer = operator === "+" ? left + right : left - right;
    const operands = [left, right];
    return this.fields(
      {
        operands,
        operator,
        answer,
        initial_counts: [...operands],
        manipulative_id: "counters",
      },
      "question.basic_operations",
      { expression: `${left} ${operator} ${right}` },
      answer,
    );
  }
}
