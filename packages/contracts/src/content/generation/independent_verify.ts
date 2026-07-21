import type { GeneratorId } from "../ids.js";
import type { AnswerValueV1, ResolvedParametersV1 } from "../types.js";

const SAFE_MAX = Number.MAX_SAFE_INTEGER;

export function verifyGeneratedAnswer(
  generatorId: GeneratorId,
  resolved: Readonly<ResolvedParametersV1>,
  answer: Readonly<AnswerValueV1>,
): string[] {
  const issues: string[] = [];
  switch (generatorId) {
    case "addition_v1":
      verifyInteger(answer, sum(readIntegers(resolved.operands, issues, "operands")), issues);
      break;
    case "subtraction_v1": {
      const operands = readIntegers(resolved.operands, issues, "operands");
      const expected = operands.length < 2
        ? null
        : operands.slice(1).reduce((value, operand) => value - operand, operands[0]!);
      verifyInteger(answer, expected, issues);
      break;
    }
    case "multiplication_v1": {
      const operands = readIntegers(resolved.operands, issues, "operands");
      verifyInteger(
        answer,
        operands.length === 2 ? safeProduct(operands, issues) : null,
        issues,
      );
      break;
    }
    case "common_multiple_v1": {
      const operands = readIntegers(resolved.operands, issues, "operands");
      verifyInteger(answer, independentLcm(operands, issues), issues);
      break;
    }
    case "prime_factorization_v1": {
      const factors = readAnswerList(answer, issues);
      const value = readInteger(resolved.value, issues, "value");
      if (factors.some((factor) => !isPrimeByTrialDivision(factor))) {
        issues.push("NON_PRIME_FACTOR");
      }
      if (factors.some((factor, index) => index > 0 && factors[index - 1]! > factor)) {
        issues.push("UNSORTED_FACTORS");
      }
      if (factors.length !== resolved.factor_count) issues.push("FACTOR_COUNT_MISMATCH");
      if (value !== null && safeProduct(factors, issues) !== value) {
        issues.push("FACTOR_PRODUCT_MISMATCH");
      }
      break;
    }
    case "counting_v1": {
      const count = readInteger(resolved.count, issues, "count");
      verifyInteger(answer, count, issues);
      if (readIntegers(resolved.item_ids, issues, "item_ids").length !== count) {
        issues.push("ITEM_COUNT_MISMATCH");
      }
      break;
    }
    case "number_bonds_v1": {
      const whole = readInteger(resolved.whole, issues, "whole");
      const parts = readIntegers(resolved.parts, issues, "parts");
      const missing = readInteger(resolved.missing_part, issues, "missing_part");
      if (whole !== null && sum(parts) !== whole) issues.push("BOND_SUM_MISMATCH");
      verifyInteger(answer, missing, issues);
      break;
    }
    case "ten_frame_v1": {
      const target = readInteger(resolved.target, issues, "target");
      verifyInteger(answer, target, issues);
      if (readIntegers(resolved.occupied_cells, issues, "occupied_cells").length !== target) {
        issues.push("TEN_FRAME_COUNT_MISMATCH");
      }
      break;
    }
    case "base_ten_v1": {
      const hundreds = readInteger(resolved.hundreds, issues, "hundreds");
      const tens = readInteger(resolved.tens, issues, "tens");
      const ones = readInteger(resolved.ones, issues, "ones");
      const expected = hundreds === null || tens === null || ones === null
        ? null
        : hundreds * 100 + tens * 10 + ones;
      verifyInteger(answer, expected, issues);
      if (expected !== resolved.value) issues.push("PLACE_VALUE_MISMATCH");
      break;
    }
    case "number_line_v1": {
      const start = readInteger(resolved.start, issues, "start");
      const steps = readIntegers(resolved.signed_steps, issues, "signed_steps");
      const endpoint = start === null ? null : start + sum(steps);
      verifyInteger(answer, endpoint, issues);
      if (endpoint !== resolved.endpoint) issues.push("ENDPOINT_MISMATCH");
      break;
    }
    case "basic_operations_v1": {
      const operands = readIntegers(resolved.operands, issues, "operands");
      const operator = resolved.operator;
      const expected = operands.length !== 2
        ? null
        : operator === "+"
        ? operands[0]! + operands[1]!
        : operator === "-"
        ? operands[0]! - operands[1]!
        : null;
      if (expected === null) issues.push("INVALID_BASIC_OPERATION");
      verifyInteger(answer, expected, issues);
      break;
    }
    default: {
      const exhaustive: never = generatorId;
      issues.push(`UNKNOWN_GENERATOR:${String(exhaustive)}`);
    }
  }
  return [...new Set(issues)];
}

function verifyInteger(
  answer: Readonly<AnswerValueV1>,
  expected: number | null,
  issues: string[],
): void {
  if (answer.kind !== "integer") {
    issues.push("ANSWER_KIND");
    return;
  }
  if (expected === null || answer.value !== expected) issues.push("ANSWER_MISMATCH");
}

function readAnswerList(answer: Readonly<AnswerValueV1>, issues: string[]): number[] {
  if (answer.kind !== "integer_list") {
    issues.push("ANSWER_KIND");
    return [];
  }
  return readIntegers(answer.values, issues, "answer.values");
}

function readInteger(value: unknown, issues: string[], name: string): number | null {
  if (!Number.isSafeInteger(value)) {
    issues.push(`INVALID_INTEGER:${name}`);
    return null;
  }
  return value as number;
}

function readIntegers(value: unknown, issues: string[], name: string): number[] {
  if (!Array.isArray(value) || value.some((entry) => !Number.isSafeInteger(entry))) {
    issues.push(`INVALID_INTEGER_LIST:${name}`);
    return [];
  }
  return value as number[];
}

function sum(values: readonly number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

function safeProduct(values: readonly number[], issues: string[]): number | null {
  let result = 1;
  for (const value of values) {
    if (value !== 0 && Math.abs(result) > Math.floor(SAFE_MAX / Math.abs(value))) {
      issues.push("PRODUCT_OVERFLOW");
      return null;
    }
    result *= value;
  }
  return result;
}

function independentLcm(values: readonly number[], issues: string[]): number | null {
  if (values.length < 2 || values.some((value) => value < 1)) {
    issues.push("LCM_OPERANDS");
    return null;
  }
  const maximumExponents = new Map<number, number>();
  for (const value of values) {
    for (const [prime, exponent] of primeExponentMap(value)) {
      maximumExponents.set(prime, Math.max(maximumExponents.get(prime) ?? 0, exponent));
    }
  }
  const factors: number[] = [];
  for (const [prime, exponent] of maximumExponents) {
    for (let count = 0; count < exponent; count += 1) factors.push(prime);
  }
  return safeProduct(factors, issues);
}

function primeExponentMap(value: number): Map<number, number> {
  let remainder = value;
  const result = new Map<number, number>();
  for (let divisor = 2; divisor <= Math.floor(remainder / divisor); divisor += 1) {
    while (remainder % divisor === 0) {
      result.set(divisor, (result.get(divisor) ?? 0) + 1);
      remainder /= divisor;
    }
  }
  if (remainder > 1) result.set(remainder, (result.get(remainder) ?? 0) + 1);
  return result;
}

function isPrimeByTrialDivision(value: number): boolean {
  if (!Number.isSafeInteger(value) || value < 2) return false;
  for (let divisor = 2; divisor <= Math.floor(value / divisor); divisor += 1) {
    if (value % divisor === 0) return false;
  }
  return true;
}
