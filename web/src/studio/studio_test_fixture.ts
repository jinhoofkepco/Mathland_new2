import type { ContentDraft } from "../cloud/cloud_port";

export function studioPackageFixture(): ContentDraft["package"] {
  const band = <T extends "intro" | "practice" | "challenge">(band_id: T) => ({
    band_id,
    generator_id: "addition_v1" as const,
    generator_parameters: { operand_count: 2, operand_min: 0, operand_max: 9, place_mode: "ones_digit", carry: "allow" },
    answer_layout: { id: "numeric_keypad" as const },
    manipulative: { id: "none" as const, config: {}, initial_state: {} },
  });
  return {
    schema_version: 1,
    content_version: "1.0.0",
    activity_id: "addition_ones",
    localizations: { "ko-KR": { title: "덧셈 탐험", description: "더해 보아요", tutorial_steps: ["수를 살펴봐요"] } },
    icon_id: "addition_ones",
    scene_id: "activity_run",
    run: {
      starting_hearts: 3,
      goal: { kind: "correct_answers", target: 10 },
      timer: { enabled: false, seconds: 60, profile_can_disable: true },
      rewards: { apples_per_correct: 2, completion_apples: 5 },
      combo_thresholds: [2, 4, 7],
      boss_every_correct: 5,
      effects: { correct: "correct", wrong: "wrong", combo: "combo_1", boss: "boss", level_up: "level_up", reward: "reward", health_loss: "health_loss" },
    },
    difficulty_bands: [band("intro"), band("practice"), band("challenge")],
    adaptive_policy: { enabled_by_default: false, min_band_id: "intro", max_band_id: "challenge", window_size: 5, promote_correctness: 0.8, demote_correctness: 0.4 },
    validation_samples: [
      { band_id: "intro", seed: 1, expected_answer: { kind: "integer", value: 8 } },
    ],
  };
}
