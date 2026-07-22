export const UINT32_MAX = 0xffff_ffff;
export const UINT32_RANGE = 0x1_0000_0000;
const ZERO_SEED_STATE = 0x6d2b_79f5;

export function isUint32(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= UINT32_MAX;
}

export function isSupportedRngRange(minimum: unknown, maximum: unknown): boolean {
  return (
    Number.isSafeInteger(minimum) &&
    Number.isSafeInteger(maximum) &&
    (maximum as number) >= (minimum as number) &&
    (maximum as number) - (minimum as number) < UINT32_RANGE
  );
}

export class SeededRng {
  #state: number;

  constructor(seed: number) {
    if (!isUint32(seed)) {
      throw new RangeError("RNG seed must be an unsigned 32-bit integer");
    }
    this.#state = seed === 0 ? ZERO_SEED_STATE : seed;
  }

  get state(): number {
    return this.#state;
  }

  nextU32(): number {
    let value = this.#state;
    value ^= value << 13;
    value ^= value >>> 17;
    value ^= value << 5;
    this.#state = value >>> 0;
    return this.#state;
  }

  rangeInt(minimum: number, maximum: number): number {
    if (!isSupportedRngRange(minimum, maximum)) {
      throw new RangeError("RNG range exceeds one unsigned 32-bit draw");
    }
    const span = maximum - minimum + 1;
    return minimum + (this.nextU32() % span);
  }

  weightedIndex(weights: readonly number[]): number {
    if (
      weights.length === 0 ||
      weights.some((weight) => !Number.isSafeInteger(weight) || weight <= 0)
    ) {
      return -1;
    }
    const total = weights.reduce((sum, weight) => sum + weight, 0);
    if (!Number.isSafeInteger(total) || total > UINT32_RANGE) return -1;
    const target = this.nextU32() % total;
    let cursor = 0;
    for (let index = 0; index < weights.length; index += 1) {
      cursor += weights[index]!;
      if (target < cursor) return index;
    }
    return -1;
  }
}
