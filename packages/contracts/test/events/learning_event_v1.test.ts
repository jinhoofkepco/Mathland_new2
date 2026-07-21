import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { LearningEventV1Schema } from "../../src/index.js";

const fixture = JSON.parse(
  readFileSync(
    new URL("../../../../tests/fixtures/contracts/learning_event_v1.json", import.meta.url),
    "utf8",
  ),
) as Record<string, unknown>;

const common = (eventType: string, includeSession: boolean): Record<string, unknown> => ({
  contract_version: fixture.contract_version,
  event_id: fixture.event_id,
  profile_id: fixture.profile_id,
  device_id: fixture.device_id,
  ...(includeSession ? { session_id: fixture.session_id } : {}),
  sequence: fixture.sequence,
  client_timestamp: fixture.client_timestamp,
  event_type: eventType,
});

describe("LearningEventV1 Godot parity", () => {
  it("parses the exact legacy-integer Godot fixture without changing keys or values", () => {
    const parsed = LearningEventV1Schema.parse(fixture);

    expect(new Set(Object.keys(parsed))).toEqual(new Set(Object.keys(fixture)));
    expect(parsed).toEqual(fixture);
    expect(parsed.event_type).toBe("answer_submitted");
    if (parsed.event_type !== "answer_submitted") {
      throw new Error("Expected the answer_submitted fixture variant");
    }
    expect(parsed.submitted_answer).toBe(7);
    expect(parsed.correct_answer).toBe(7);
  });

  it("rejects unknown common keys, non-v4 UUIDs, and nonpositive sequences", () => {
    expect(LearningEventV1Schema.safeParse({ ...fixture, injected: true }).success).toBe(false);
    expect(LearningEventV1Schema.safeParse({ ...fixture, event_id: "not-a-uuid" }).success).toBe(
      false,
    );
    expect(
      LearningEventV1Schema.safeParse({
        ...fixture,
        event_id: "1ebc4ec2-9c32-1f7d-9c3c-d21c284d7a31",
      }).success,
    ).toBe(false);
    expect(LearningEventV1Schema.safeParse({ ...fixture, sequence: 0 }).success).toBe(false);
  });

  it("requires session IDs for run events and permits them to be absent only for reward events", () => {
    const answerWithoutSession = { ...fixture };
    delete answerWithoutSession.session_id;
    expect(LearningEventV1Schema.safeParse(answerWithoutSession).success).toBe(false);

    const runStarted = {
      ...common("run_started", true),
      activity_id: "foundations_ten_frame",
      content_version: "1.0.0",
    };
    expect(LearningEventV1Schema.safeParse(runStarted).success).toBe(true);
    const runStartedWithoutSession = { ...runStarted };
    Reflect.deleteProperty(runStartedWithoutSession, "session_id");
    expect(LearningEventV1Schema.safeParse(runStartedWithoutSession).success).toBe(false);

    const runCompleted = {
      ...common("run_completed", true),
      completion_reason: "target_reached",
      final_score: 8,
      final_health: 2,
      earned_rewards: { apples: 4 },
    };
    expect(LearningEventV1Schema.safeParse(runCompleted).success).toBe(true);
    const runCompletedWithoutSession = { ...runCompleted };
    Reflect.deleteProperty(runCompletedWithoutSession, "session_id");
    expect(LearningEventV1Schema.safeParse(runCompletedWithoutSession).success).toBe(false);

    const collection = {
      ...common("collection_unlocked", false),
      collection_id: "island_garden",
    };
    const coupon = { ...common("coupon_earned", false), coupon_id: "guardian_bonus_1" };
    expect(LearningEventV1Schema.safeParse(collection).success).toBe(true);
    expect(LearningEventV1Schema.safeParse(coupon).success).toBe(true);
    expect(
      LearningEventV1Schema.safeParse({ ...collection, session_id: "optional-session" }).success,
    ).toBe(true);
  });

  it("accepts exactly the five strict type-specific shapes", () => {
    const variants = [
      {
        ...common("run_started", true),
        activity_id: "addition_ones",
        content_version: "1.0.0",
      },
      fixture,
      {
        ...common("run_completed", true),
        completion_reason: "health_depleted",
        final_score: 3,
        final_health: 0,
        earned_rewards: { apples: 6 },
      },
      { ...common("collection_unlocked", false), collection_id: "first_shell" },
      { ...common("coupon_earned", false), coupon_id: "week_one" },
    ];

    for (const variant of variants) {
      expect(LearningEventV1Schema.safeParse(variant).success).toBe(true);
    }
    expect(
      LearningEventV1Schema.safeParse({ ...variants[3], coupon_id: "wrong-type-field" }).success,
    ).toBe(false);
    expect(
      LearningEventV1Schema.safeParse({ ...variants[0], final_score: 1 }).success,
    ).toBe(false);
  });

  it("accepts strict structured answers and rejects invented keys", () => {
    const structured = {
      ...fixture,
      submitted_answer: { kind: "integer_list", values: [2, 2, 3], order_matters: true },
      correct_answer: { kind: "integer", value: 12 },
    };
    expect(LearningEventV1Schema.safeParse(structured).success).toBe(true);
    expect(
      LearningEventV1Schema.safeParse({
        ...structured,
        submitted_answer: { ...structured.submitted_answer, extra: true },
      }).success,
    ).toBe(false);
    expect(
      LearningEventV1Schema.safeParse({ ...fixture, submitted_answer: Number.MAX_SAFE_INTEGER + 1 })
        .success,
    ).toBe(false);
  });

  it("enforces safe integer boundaries and nonnegative counters and rewards", () => {
    for (const key of [
      "sequence",
      "question_seed",
      "response_duration_ms",
      "hints",
      "health_delta",
      "combo",
    ]) {
      expect(
        LearningEventV1Schema.safeParse({ ...fixture, [key]: Number.MAX_SAFE_INTEGER + 1 })
          .success,
      ).toBe(false);
    }
    for (const key of ["question_seed", "response_duration_ms", "hints", "combo"]) {
      expect(LearningEventV1Schema.safeParse({ ...fixture, [key]: -1 }).success).toBe(false);
    }
    expect(
      LearningEventV1Schema.safeParse({ ...fixture, reward_delta: { apples: -1 } }).success,
    ).toBe(false);
    expect(
      LearningEventV1Schema.safeParse({ ...fixture, reward_delta: { "": 1 } }).success,
    ).toBe(false);
    expect(
      LearningEventV1Schema.safeParse({
        ...fixture,
        resolved_parameters: { ratio: Number.POSITIVE_INFINITY },
      }).success,
    ).toBe(false);
  });

  it("uses the same unsigned 32-bit question-seed contract as the generators", () => {
    expect(
      LearningEventV1Schema.safeParse({ ...fixture, question_seed: 0xffff_ffff }).success,
    ).toBe(true);
    expect(
      LearningEventV1Schema.safeParse({ ...fixture, question_seed: 0x1_0000_0000 }).success,
    ).toBe(false);
  });

  it.each(["final_score", "final_health"] as const)(
    "rejects negative and unsafe run-completed %s values",
    (field) => {
      const runCompleted = {
        ...common("run_completed", true),
        completion_reason: "target_reached",
        final_score: 8,
        final_health: 2,
        earned_rewards: { apples: 4 },
      };

      for (const invalid of [-1, Number.MAX_SAFE_INTEGER + 1]) {
        expect(
          LearningEventV1Schema.safeParse({ ...runCompleted, [field]: invalid }).success,
        ).toBe(false);
      }
    },
  );

  it.each([-1, Number.MAX_SAFE_INTEGER + 1])(
    "rejects invalid run-completed earned reward value %s",
    (invalid) => {
      const runCompleted = {
        ...common("run_completed", true),
        completion_reason: "target_reached",
        final_score: 8,
        final_health: 2,
        earned_rewards: { apples: invalid },
      };

      expect(LearningEventV1Schema.safeParse(runCompleted).success).toBe(false);
    },
  );

  it.each(["submitted_answer", "correct_answer"] as const)(
    "rejects unsafe structured integer and integer-list elements in %s",
    (field) => {
      const invalidAnswers = [
        { kind: "integer", value: Number.MAX_SAFE_INTEGER + 1 },
        { kind: "integer", value: Number.MIN_SAFE_INTEGER - 1 },
        {
          kind: "integer_list",
          values: [2, Number.MAX_SAFE_INTEGER + 1],
          order_matters: true,
        },
        {
          kind: "integer_list",
          values: [Number.MIN_SAFE_INTEGER - 1, 2],
          order_matters: false,
        },
      ];

      for (const invalidAnswer of invalidAnswers) {
        expect(
          LearningEventV1Schema.safeParse({ ...fixture, [field]: invalidAnswer }).success,
        ).toBe(false);
      }
    },
  );

  it("accepts only calendar-valid canonical UTC timestamps compatible with Godot", () => {
    expect(
      LearningEventV1Schema.safeParse({
        ...fixture,
        client_timestamp: "2024-02-29T23:59:59Z",
      }).success,
    ).toBe(true);

    for (const clientTimestamp of [
      "2026-02-29T09:00:00Z",
      "2026-04-31T09:00:00Z",
      "2026-07-21T24:00:00Z",
      "2026-07-21T09:00:00+00:00",
      "2026-07-21T09:00:00.000Z",
      "0000-01-01T00:00:00Z",
    ]) {
      expect(
        LearningEventV1Schema.safeParse({ ...fixture, client_timestamp: clientTimestamp }).success,
      ).toBe(false);
    }
  });
});
