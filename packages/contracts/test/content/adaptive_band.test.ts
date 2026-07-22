import { describe, expect, it } from "vitest";

import { selectAdaptiveBand } from "../../src/index.js";

const ACTIVITY = {
  activity_id: "addition_ones",
  content_version: "1.2.3",
  difficulty_bands: [
    { band_id: "intro" },
    { band_id: "practice" },
    { band_id: "challenge" },
  ],
  adaptive_policy: {
    enabled_by_default: false,
    min_band_id: "intro",
    max_band_id: "challenge",
    window_size: 4,
    promote_correctness: 0.75,
    demote_correctness: 0.35,
  },
  run: { starting_hearts: 3 },
  rewards: { apples: 2 },
} as const;

function answer(sequence: number, correctness: boolean, hints = 0, questionSeed = sequence) {
  return {
    event_type: "answer_submitted",
    activity_id: "addition_ones",
    content_version: "1.2.3",
    sequence,
    question_seed: questionSeed,
    correctness,
    hints,
  };
}

describe("adaptive band selector", () => {
  it("returns the authored fixed band without touching history when disabled", () => {
    const unreadableHistory = new Proxy([], {
      get() {
        throw new Error("history must not be read");
      },
    });
    expect(selectAdaptiveBand(ACTIVITY, "practice", unreadableHistory, false)).toBe("practice");
    expect(selectAdaptiveBand({ ...ACTIVITY, adaptive_policy: undefined }, "practice", [], true)).toBe(
      "practice",
    );
  });

  it("keeps the current band until one complete authored window exists", () => {
    expect(selectAdaptiveBand(ACTIVITY, "practice", [], true)).toBe("practice");
    expect(
      selectAdaptiveBand(ACTIVITY, "practice", [answer(1, true), answer(2, true)], true),
    ).toBe("practice");
  });

  it("promotes or demotes at thresholds by at most one adjacent band", () => {
    expect(
      selectAdaptiveBand(
        ACTIVITY,
        "intro",
        [answer(1, true), answer(2, true), answer(3, true), answer(4, false)],
        true,
      ),
    ).toBe("practice");
    expect(
      selectAdaptiveBand(
        ACTIVITY,
        "challenge",
        [answer(1, false), answer(2, true), answer(3, false), answer(4, false)],
        true,
      ),
    ).toBe("practice");
  });

  it("filters by pinned activity/version, uses only the latest window, and applies penalties", () => {
    const irrelevant = { ...answer(99, false), activity_id: "subtraction_ones" };
    const oldFailures = [answer(1, false), answer(2, false), answer(3, false), answer(4, false)];
    const latest = [
      answer(5, true, 1),
      answer(6, true),
      answer(7, true),
      answer(8, true),
    ];
    expect(
      selectAdaptiveBand(ACTIVITY, "practice", [...oldFailures, irrelevant, ...latest], true),
    ).toBe("practice");
    expect(
      selectAdaptiveBand(
        ACTIVITY,
        "practice",
        [answer(1, false, 0, 7), answer(2, false, 0, 7), answer(3, true), answer(4, true)],
        true,
      ),
    ).toBe("practice");
  });

  it("clamps to authored bounds and never mutates activity or history", () => {
    const bounded = {
      ...ACTIVITY,
      adaptive_policy: { ...ACTIVITY.adaptive_policy, min_band_id: "practice", max_band_id: "challenge" },
    };
    const history = [answer(1, false), answer(2, false), answer(3, false), answer(4, false)];
    const activitySnapshot = structuredClone(bounded);
    const historySnapshot = structuredClone(history);
    expect(selectAdaptiveBand(bounded, "practice", history, true)).toBe("practice");
    expect(bounded).toEqual(activitySnapshot);
    expect(history).toEqual(historySnapshot);
  });

  it("ignores nonpositive, unsafe, or non-uint32 event integers", () => {
    const invalidEvents = [
      answer(0, true),
      answer(Number.MAX_SAFE_INTEGER + 1, true),
      answer(2, true, 0, 0x1_0000_0000),
      answer(3, true, Number.MAX_SAFE_INTEGER + 1),
    ];
    const validButIncomplete = [answer(10, true), answer(11, true), answer(12, true)];

    for (const invalidEvent of invalidEvents) {
      expect(selectAdaptiveBand(ACTIVITY, "intro", [invalidEvent, ...validButIncomplete], true)).toBe(
        "intro",
      );
    }
  });
});
