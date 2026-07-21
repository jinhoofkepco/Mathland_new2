import {
  ACTIVITY_GENERATOR_IDS,
  ACTIVITY_IDS,
  type ActivityId,
  type ActivityPackageDraftV1,
  type ActivityPackageV1,
  type ContentManifestV1,
  contentChecksum,
} from "../../src/index.js";

const BAND_IDS = ["intro", "practice", "challenge"] as const;
const VALIDATION_SEEDS = [1, 7, 42, 20260721] as const;

export function makeValidDraft(activityId: ActivityId = "addition_ones"): ActivityPackageDraftV1 {
  const generatorId = ACTIVITY_GENERATOR_IDS[activityId];

  return {
    schema_version: 1,
    content_version: "1.0.0",
    activity_id: activityId,
    localizations: {
      "ko-KR": {
        title: `${activityId} 탐험`,
        description: "놀이하며 수학 원리를 익혀요.",
        tutorial_steps: ["그림을 살펴보고 답을 골라요."],
      },
    },
    icon_id: activityId,
    scene_id: "activity_run",
    run: {
      starting_hearts: 3,
      goal: { kind: "correct_answers", target: 10 },
      timer: { enabled: true, seconds: 60, profile_can_disable: true },
      rewards: { apples_per_correct: 2, completion_apples: 5 },
      combo_thresholds: [2, 4, 7],
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
    difficulty_bands: BAND_IDS.map((bandId, index) => ({
      band_id: bandId,
      generator_id: generatorId,
      generator_parameters: {
        operand_min: index,
        operand_max: 9 + index,
        carry: index === 0 ? "forbid" : "allow",
      },
      answer_layout: {
        id: generatorId === "prime_factorization_v1" ? "factor_slots" : "numeric_keypad",
      },
      manipulative: { id: "none", config: {}, initial_state: {} },
    })),
    adaptive_policy: {
      enabled_by_default: false,
      min_band_id: "intro",
      max_band_id: "challenge",
      window_size: 5,
      promote_correctness: 0.8,
      demote_correctness: 0.4,
    },
    validation_samples: BAND_IDS.flatMap((bandId) =>
      VALIDATION_SEEDS.map((seed) => ({
        band_id: bandId,
        seed,
        expected_answer: { kind: "integer" as const, value: seed % 10 },
      })),
    ),
  };
}

export function makePublished(
  draft: ActivityPackageDraftV1 = makeValidDraft(),
): ActivityPackageV1 {
  return { ...draft, checksum: contentChecksum(draft) };
}

export function makeAllPublishedPackages(): ActivityPackageV1[] {
  return ACTIVITY_IDS.map((activityId) => makePublished(makeValidDraft(activityId)));
}

export function makeValidManifest(packages: readonly ActivityPackageV1[]): ContentManifestV1 {
  return {
    schema_version: 1,
    manifest_version: "1.0.0",
    published_at: "2026-07-21T00:00:00Z",
    activity_order: [...ACTIVITY_IDS],
    packages: packages.map((activityPackage) => ({
      activity_id: activityPackage.activity_id,
      content_version: activityPackage.content_version,
      path: `content/packages/${activityPackage.activity_id}/${activityPackage.content_version}.json`,
      checksum: activityPackage.checksum,
    })),
  };
}
