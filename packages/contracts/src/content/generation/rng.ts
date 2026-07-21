const UINT32_MAX = 0xffff_ffff;
const ZERO_SEED_STATE = 0x6d2b_79f5;

export class SeededRng {
  #state: number;

  constructor(seed: number) {
    if (!Number.isSafeInteger(seed) || seed < 0) {
      throw new RangeError("RNG seed must be a nonnegative safe integer");
    }
    const normalized = seed >>> 0;
    this.#state = normalized === 0 ? ZERO_SEED_STATE : normalized;
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
    if (!Number.isSafeInteger(minimum) || !Number.isSafeInteger(maximum) || maximum < minimum) {
      throw new RangeError("RNG range must contain ordered safe integers");
    }
    const span = maximum - minimum + 1;
    if (!Number.isSafeInteger(span) || span < 1 || span > UINT32_MAX + 1) {
      throw new RangeError("RNG range exceeds one unsigned 32-bit draw");
    }
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
    if (!Number.isSafeInteger(total) || total > UINT32_MAX + 1) return -1;
    const target = this.nextU32() % total;
    let cursor = 0;
    for (let index = 0; index < weights.length; index += 1) {
      cursor += weights[index]!;
      if (target < cursor) return index;
    }
    return -1;
  }
}
