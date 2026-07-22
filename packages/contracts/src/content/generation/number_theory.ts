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
const MAX_SAFE_FACTOR_SLOTS = 52;
const MAX_AUTHORED_PRIMES = 128;
// This fixed witness set is deterministic over every 64-bit integer, so it is
// an exact primality decision over MathLand's smaller safe-integer domain.
const MILLER_RABIN_BASES = [2n, 325n, 9375n, 28178n, 450775n, 9780504n, 1795265022n];

type Parameters = Readonly<Record<string, unknown>>;

function hasExactKeys(parameters: Parameters, expected: readonly string[]): boolean {
  const actual = Object.keys(parameters).sort();
  return actual.length === expected.length && [...expected].sort().every((key, index) => key === actual[index]);
}

function isPositiveSafeInteger(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 1;
}

function report(issues: string[]): GeneratorValidationResult {
  return { valid: issues.length === 0, issues };
}

function gcd(left: number, right: number): number {
  let a = left;
  let b = right;
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}

function safeLcm(left: number, right: number): number | null {
  const quotient = left / gcd(left, right);
  return quotient > Math.floor(SAFE_INTEGER_MAX / right) ? null : quotient * right;
}

function modularPower(base: bigint, exponent: bigint, modulus: bigint): bigint {
  let value = base % modulus;
  let power = exponent;
  let result = 1n;
  while (power > 0n) {
    if ((power & 1n) === 1n) result = (result * value) % modulus;
    power >>= 1n;
    value = (value * value) % modulus;
  }
  return result;
}

function isPrime(value: number): boolean {
  if (!isPositiveSafeInteger(value) || value < 2) return false;
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

abstract class NumberTheoryGenerator implements QuestionGeneratorContract {
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
}

export class CommonMultipleGenerator extends NumberTheoryGenerator {
  readonly generatorId = "common_multiple_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["operand_count", "operand_min", "operand_max", "require_distinct"])) issues.push("PARAMETER_KEYS");
    if (values.operand_count !== 2 && values.operand_count !== 3) issues.push("OPERAND_COUNT");
    if (
      !isPositiveSafeInteger(values.operand_min) ||
      !isPositiveSafeInteger(values.operand_max) ||
      (values.operand_max as number) < (values.operand_min as number)
    ) {
      issues.push("OPERAND_RANGE");
    } else if (!isSupportedRngRange(values.operand_min, values.operand_max)) {
      issues.push("OPERAND_RANGE_WIDTH");
    }
    if (typeof values.require_distinct !== "boolean") issues.push("REQUIRE_DISTINCT");
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
      if (parameters.require_distinct && new Set(operands).size !== operands.length) continue;
      let answer = 1;
      let overflowed = false;
      for (const operand of operands) {
        const next = safeLcm(answer, operand);
        if (next === null) {
          overflowed = true;
          break;
        }
        answer = next;
      }
      if (overflowed) continue;
      this.lastError = "";
      return {
        resolved_parameters: { operands, operator: "lcm", answer },
        prompt: { key: "question.common_multiple", args: { expression: operands.join(" ") } },
        correct_answer: { kind: "integer", value: answer },
      };
    }
    return this.unsatisfiable();
  }
}

export class PrimeFactorizationGenerator extends NumberTheoryGenerator {
  readonly generatorId = "prime_factorization_v1" as const;

  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult {
    const values = parameters as Parameters;
    const issues: string[] = [];
    if (!hasExactKeys(values, ["value_min", "value_max", "factor_count_min", "factor_count_max", "allowed_primes"])) issues.push("PARAMETER_KEYS");
    if (
      !isPositiveSafeInteger(values.value_min) ||
      !isPositiveSafeInteger(values.value_max) ||
      (values.value_max as number) < (values.value_min as number)
    ) {
      issues.push("VALUE_RANGE");
    }
    if (
      !isPositiveSafeInteger(values.factor_count_min) ||
      !isPositiveSafeInteger(values.factor_count_max) ||
      (values.factor_count_max as number) < (values.factor_count_min as number) ||
      (values.factor_count_max as number) > MAX_SAFE_FACTOR_SLOTS
    ) {
      issues.push("FACTOR_COUNT_RANGE");
    }
    if (!Array.isArray(values.allowed_primes) || values.allowed_primes.length === 0) {
      issues.push("ALLOWED_PRIMES");
    } else {
      const primes = values.allowed_primes as unknown[];
      if (primes.length > MAX_AUTHORED_PRIMES) issues.push("ALLOWED_PRIMES_SIZE");
      if (primes.some((prime) => !isPrime(prime as number))) issues.push("ALLOWED_PRIMES");
      if (new Set(primes).size !== primes.length) issues.push("DUPLICATE_PRIMES");
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
    const allowedPrimes = [...(parameters.allowed_primes as number[])];
    const rng = this.rng(seed);
    if (rng === null) return null;
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
      const factorCount = rng.rangeInt(
        parameters.factor_count_min as number,
        parameters.factor_count_max as number,
      );
      const factors: number[] = [];
      let value = 1;
      let overflowed = false;
      for (let slot = 0; slot < factorCount; slot += 1) {
        const factor = allowedPrimes[rng.rangeInt(0, allowedPrimes.length - 1)]!;
        factors.push(factor);
        if (value > Math.floor(SAFE_INTEGER_MAX / factor)) {
          overflowed = true;
        } else if (!overflowed) {
          value *= factor;
        }
      }
      if (overflowed || value < (parameters.value_min as number) || value > (parameters.value_max as number)) continue;
      factors.sort((left, right) => left - right);
      const independentlyFactored = factorByAuthoredPrimes(value, allowedPrimes);
      if (
        independentlyFactored === null ||
        independentlyFactored.length !== factors.length ||
        independentlyFactored.some((factor, index) => factor !== factors[index])
      ) {
        continue;
      }
      this.lastError = "";
      return {
        resolved_parameters: {
          value,
          factors: [...factors],
          factor_count: factorCount,
          allowed_primes: [...allowedPrimes],
        },
        prompt: { key: "question.prime_factorization", args: { value } },
        correct_answer: { kind: "integer_list", values: [...factors], order_matters: false },
      };
    }
    return this.unsatisfiable();
  }
}

function factorByAuthoredPrimes(value: number, allowedPrimes: readonly number[]): number[] | null {
  let remainder = value;
  const factors: number[] = [];
  const sortedPrimes = [...allowedPrimes].sort((left, right) => left - right);
  for (const prime of sortedPrimes) {
    while (remainder % prime === 0) {
      factors.push(prime);
      remainder /= prime;
    }
  }
  return remainder === 1 ? factors : null;
}
