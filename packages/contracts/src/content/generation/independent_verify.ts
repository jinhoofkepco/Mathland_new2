import type { GeneratorId } from "../ids.js";
import type { AnswerValueV1, ResolvedParametersV1 } from "../types.js";

const SAFE_MAX = Number.MAX_SAFE_INTEGER;
// Deterministic for every 64-bit integer, and therefore exact over the smaller
// JavaScript safe-integer domain accepted by the content contracts.
const MILLER_RABIN_BASES = [2n, 325n, 9375n, 28178n, 450775n, 9780504n, 1795265022n];

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
      if (factors.some((factor) => !isPrimeDeterministically(factor))) {
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

  let result = 1;
  for (const value of values) {
    const quotient = result / greatestCommonDivisor(result, value);
    const next = safeProduct([quotient, value], issues);
    if (next === null) return null;
    result = next;
  }
  return result;
}

function greatestCommonDivisor(left: number, right: number): number {
  let a = left;
  let b = right;
  while (b !== 0) {
    [a, b] = [b, a % b];
  }
  return a;
}

function modularPower(base: bigint, exponent: bigint, modulus: bigint): bigint {
  let factor = base % modulus;
  let power = exponent;
  let result = 1n;
  while (power > 0n) {
    if ((power & 1n) === 1n) result = (result * factor) % modulus;
    power >>= 1n;
    factor = (factor * factor) % modulus;
  }
  return result;
}

function isPrimeDeterministically(value: number): boolean {
  if (!Number.isSafeInteger(value) || value < 2) return false;
  if (value === 2 || value === 3) return true;
  if (value % 2 === 0) return false;

  const candidate = BigInt(value);
  let oddPart = candidate - 1n;
  let twos = 0;
  while ((oddPart & 1n) === 0n) {
    oddPart >>= 1n;
    twos += 1;
  }

  for (const rawBase of MILLER_RABIN_BASES) {
    const base = rawBase % candidate;
    if (base === 0n) continue;
    let witness = modularPower(base, oddPart, candidate);
    if (witness === 1n || witness === candidate - 1n) continue;

    let composite = true;
    for (let round = 1; round < twos; round += 1) {
      witness = (witness * witness) % candidate;
      if (witness === candidate - 1n) {
        composite = false;
        break;
      }
    }
    if (composite) return false;
  }
  return true;
}
