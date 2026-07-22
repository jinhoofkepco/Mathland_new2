import { describe, expect, expectTypeOf, it } from "vitest";

import {
  ACTIVITY_GENERATOR_IDS,
  ACTIVITY_IDS,
  ANSWER_LAYOUT_IDS,
  DIALOGUE_IDS,
  EFFECT_PRESET_IDS,
  GENERATOR_IDS,
  ICON_IDS,
  MANIPULATIVE_IDS,
  SCENE_IDS,
  type ActivityPackageDraftV1,
  type ActivityPackageV1,
  type AnswerValueV1,
  type ContentManifestV1,
  type QuestionInstanceV1,
  type ValidationReport,
} from "../../src/index.js";

describe("content contract IDs", () => {
  it("publishes the complete 1.0 activity catalogue", () => {
    expect(ACTIVITY_IDS).toEqual([
      "addition_ones",
      "subtraction_ones",
      "multiplication",
      "common_multiples_lcm",
      "prime_factorization",
      "foundations_counting",
      "foundations_number_bonds",
      "foundations_ten_frame",
      "foundations_base_ten",
      "foundations_number_line",
      "foundations_basic_operations",
    ]);
    expect(GENERATOR_IDS).toEqual([
      "addition_v1",
      "subtraction_v1",
      "multiplication_v1",
      "common_multiple_v1",
      "prime_factorization_v1",
      "counting_v1",
      "number_bonds_v1",
      "ten_frame_v1",
      "base_ten_v1",
      "number_line_v1",
      "basic_operations_v1",
    ]);
    expect(ACTIVITY_GENERATOR_IDS).toEqual(
      Object.fromEntries(ACTIVITY_IDS.map((activityId, index) => [activityId, GENERATOR_IDS[index]])),
    );
  });

  it("publishes every runtime resource allowlist as readonly data", () => {
    expect(MANIPULATIVE_IDS).toEqual([
      "none",
      "counters",
      "ten_frame",
      "base_ten",
      "number_line",
      "answer_slots",
    ]);
    expect(ANSWER_LAYOUT_IDS).toEqual([
      "numeric_keypad",
      "choice_grid",
      "factor_slots",
      "manipulative_submit",
    ]);
    expect(SCENE_IDS).toEqual(["activity_run"]);
    expect(EFFECT_PRESET_IDS).toEqual([
      "correct",
      "wrong",
      "combo_1",
      "combo_2",
      "boss",
      "health_loss",
      "target_reached",
      "level_up",
      "health_depleted",
      "reward",
      "collection",
      "coupon",
    ]);
    expect(ICON_IDS).toEqual([
      ...ACTIVITY_IDS,
      "correct",
      "wrong",
      "heart",
      "speaker",
    ]);
    expect(DIALOGUE_IDS).toEqual([
      "moa_home_welcome",
      "moa_tutorial_counting",
      "moa_tutorial_number_bonds",
      "moa_tutorial_ten_frame",
      "moa_tutorial_base_ten",
      "moa_tutorial_number_line",
      "moa_tutorial_basic_operations",
      "moa_reward",
      "moa_level_up",
    ]);

    expectTypeOf(ACTIVITY_IDS).toMatchTypeOf<readonly string[]>();
    expectTypeOf(GENERATOR_IDS).toMatchTypeOf<readonly string[]>();
    expectTypeOf(EFFECT_PRESET_IDS).toMatchTypeOf<readonly string[]>();
  });
});

describe("public content types", () => {
  it("describe the complete draft, published, manifest, question, and report shapes", () => {
    const answer = { kind: "integer", value: 7 } as const satisfies AnswerValueV1;
    const question = {
      contract_version: 1,
      activity_id: "addition_ones",
      content_version: "1.0.0",
      generator_id: "addition_v1",
      band_id: "intro",
      seed: 42,
      resolved_parameters: { left: 3, right: 4, operands: [3, 4] },
      prompt: { key: "question.addition", args: { left: 3, right: 4 } },
      correct_answer: answer,
      answer_layout: { id: "numeric_keypad" },
      manipulative: { id: "none", config: {}, initial_state: {} },
    } satisfies QuestionInstanceV1;
    const draft = {
      schema_version: 1,
      content_version: "1.0.0",
      activity_id: "addition_ones",
      localizations: {
        "ko-KR": { title: "덧셈", description: "더해요", tutorial_steps: ["두 수를 더해요"] },
      },
      icon_id: "addition_ones",
      scene_id: "activity_run",
      run: {
        starting_hearts: 3,
        goal: { kind: "correct_answers", target: 10 },
        timer: { enabled: true, seconds: 60, profile_can_disable: true },
        rewards: { apples_per_correct: 2, completion_apples: 5 },
        combo_thresholds: [2, 4, 6],
        boss_every_correct: 5,
        effects: {
          correct: "correct",
          wrong: "wrong",
          combo: "combo_1",
          boss: "boss",
          level_up: "level_up",
          reward: "reward",
          health_loss: "health_loss",
        },
      },
      difficulty_bands: [
        {
          band_id: "intro",
          generator_id: "addition_v1",
          generator_parameters: { operand_count: 2 },
          answer_layout: { id: "numeric_keypad" },
          manipulative: { id: "none", config: {}, initial_state: {} },
        },
      ],
      adaptive_policy: {
        enabled_by_default: false,
        min_band_id: "intro",
        max_band_id: "challenge",
        window_size: 5,
        promote_correctness: 0.8,
        demote_correctness: 0.4,
      },
      validation_samples: [{ band_id: "intro", seed: 42, expected_answer: answer }],
    } satisfies ActivityPackageDraftV1;
    const published = {
      ...draft,
      checksum: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    } satisfies ActivityPackageV1;
    const manifest = {
      schema_version: 1,
      manifest_version: "1.0.0",
      published_at: "2026-07-21T00:00:00Z",
      activity_order: ["addition_ones"],
      packages: [
        {
          activity_id: "addition_ones",
          content_version: "1.0.0",
          path: "content/packages/addition_ones/1.0.0.json",
          checksum: published.checksum,
        },
      ],
    } satisfies ContentManifestV1;
    const report = {
      valid: true,
      issues: [],
      samples: [question],
    } satisfies ValidationReport;

    expect(manifest.packages[0]?.checksum).toBe(published.checksum);
    expect(report.samples[0]).toEqual(question);
  });
});
