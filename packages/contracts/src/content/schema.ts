import { z } from "zod";

import {
  ACTIVITY_IDS,
  ANSWER_LAYOUT_IDS,
  EFFECT_PRESET_IDS,
  GENERATOR_IDS,
  ICON_IDS,
  MANIPULATIVE_IDS,
  SCENE_IDS,
} from "./ids.js";

export const SEMANTIC_VERSION_PATTERN = /^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$/;
export const SHA256_CHECKSUM_PATTERN = /^sha256:[0-9a-f]{64}$/;
export const PACKAGE_PATH_PATTERN = new RegExp(
  `^content/packages/(?:${ACTIVITY_IDS.join("|")})/(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.(?:0|[1-9][0-9]*)\\.json$`,
);
const NONEMPTY_TRIMMED_PATTERN = /^\S(?:[\s\S]*\S)?$/u;

const SafeIntegerSchema = z.int();
const PositiveIntegerSchema = z.int().positive();
const NonNegativeIntegerSchema = z.int().nonnegative();
const SemanticVersionSchema = z.string().regex(SEMANTIC_VERSION_PATTERN, "Expected a semantic version");
const ChecksumSchema = z.string().regex(SHA256_CHECKSUM_PATTERN, "Expected a lowercase SHA-256 checksum");

function hasAtMostCodePoints(value: string, maximum: number): boolean {
  let count = 0;
  for (const _codePoint of value) {
    count += 1;
    if (count > maximum) {
      return false;
    }
  }
  return true;
}

function trimmedText(maxLength: number) {
  return z
    .string()
    .min(1)
    .regex(NONEMPTY_TRIMMED_PATTERN, "Text must not have leading or trailing whitespace")
    .refine(
      (value) => hasAtMostCodePoints(value, maxLength),
      `Text must be at most ${maxLength} Unicode code points`,
    )
    .meta({ maxLength });
}

const AnswerValueV1Schema = z.discriminatedUnion("kind", [
  z.strictObject({
    kind: z.literal("integer"),
    value: SafeIntegerSchema,
  }),
  z.strictObject({
    kind: z.literal("integer_list"),
    values: z.array(SafeIntegerSchema).min(1).max(64),
    order_matters: z.boolean(),
  }),
]);

export const ResolvedParameterValueV1Schema = z.union([
  z.boolean(),
  SafeIntegerSchema,
  trimmedText(128),
  z.array(SafeIntegerSchema).max(128),
]);

export const ResolvedParametersV1Schema = z.record(
  z.string().min(1).max(64),
  ResolvedParameterValueV1Schema,
);

export const AnswerLayoutV1Schema = z.strictObject({
  id: z.enum(ANSWER_LAYOUT_IDS),
  options: ResolvedParametersV1Schema.optional(),
});

export const ManipulativeConfigV1Schema = z.strictObject({
  id: z.enum(MANIPULATIVE_IDS),
  config: ResolvedParametersV1Schema,
  initial_state: ResolvedParametersV1Schema,
});

const BandFields = {
  generator_id: z.enum(GENERATOR_IDS),
  generator_parameters: ResolvedParametersV1Schema,
  answer_layout: AnswerLayoutV1Schema,
  manipulative: ManipulativeConfigV1Schema,
} as const;

const IntroBandSchema = z.strictObject({ band_id: z.literal("intro"), ...BandFields });
const PracticeBandSchema = z.strictObject({ band_id: z.literal("practice"), ...BandFields });
const ChallengeBandSchema = z.strictObject({ band_id: z.literal("challenge"), ...BandFields });

export const DifficultyBandsV1Schema = z.tuple([
  IntroBandSchema,
  PracticeBandSchema,
  ChallengeBandSchema,
]);

const LocalizationSchema = z.strictObject({
  title: trimmedText(80),
  description: trimmedText(500),
  tutorial_steps: z.array(trimmedText(240)).min(1).max(12),
});

const RunSchema = z.strictObject({
  starting_hearts: PositiveIntegerSchema,
  goal: z.strictObject({
    kind: z.literal("correct_answers"),
    target: PositiveIntegerSchema,
  }),
  timer: z.strictObject({
    enabled: z.boolean(),
    seconds: PositiveIntegerSchema,
    profile_can_disable: z.boolean(),
  }),
  rewards: z.strictObject({
    apples_per_correct: PositiveIntegerSchema,
    completion_apples: PositiveIntegerSchema,
  }),
  combo_thresholds: z.tuple([
    PositiveIntegerSchema,
    PositiveIntegerSchema,
    PositiveIntegerSchema,
  ]),
  boss_every_correct: PositiveIntegerSchema,
  effects: z.strictObject({
    correct: z.enum(EFFECT_PRESET_IDS),
    wrong: z.enum(EFFECT_PRESET_IDS),
    combo: z.enum(EFFECT_PRESET_IDS),
    boss: z.enum(EFFECT_PRESET_IDS),
    level_up: z.enum(EFFECT_PRESET_IDS),
    reward: z.enum(EFFECT_PRESET_IDS),
    health_loss: z.enum(EFFECT_PRESET_IDS),
  }),
});

const AdaptivePolicySchema = z.strictObject({
  enabled_by_default: z.literal(false),
  min_band_id: trimmedText(32),
  max_band_id: trimmedText(32),
  window_size: PositiveIntegerSchema,
  promote_correctness: z.number().finite().min(0).max(1),
  demote_correctness: z.number().finite().min(0).max(1),
});

const ValidationSampleSchema = z.strictObject({
  band_id: z.enum(["intro", "practice", "challenge"]),
  seed: NonNegativeIntegerSchema,
  expected_answer: AnswerValueV1Schema,
});

const ActivityPackageDraftShape = {
  schema_version: z.literal(1),
  content_version: SemanticVersionSchema,
  activity_id: z.enum(ACTIVITY_IDS),
  localizations: z.strictObject({ "ko-KR": LocalizationSchema }),
  icon_id: z.enum(ICON_IDS),
  scene_id: z.enum(SCENE_IDS),
  run: RunSchema,
  difficulty_bands: DifficultyBandsV1Schema,
  adaptive_policy: AdaptivePolicySchema.optional(),
  validation_samples: z.array(ValidationSampleSchema).min(1).max(64),
} as const;

export const ActivityPackageDraftV1Schema = z.strictObject(ActivityPackageDraftShape);

export const ActivityPackageV1Schema = z.strictObject({
  ...ActivityPackageDraftShape,
  checksum: ChecksumSchema,
});

const ContentManifestEntryV1Schema = z.strictObject({
  activity_id: z.enum(ACTIVITY_IDS),
  content_version: SemanticVersionSchema,
  path: z.string().regex(PACKAGE_PATH_PATTERN, "Expected an allowlisted content package path"),
  checksum: ChecksumSchema,
});

export const ContentManifestV1Schema = z.strictObject({
  schema_version: z.literal(1),
  manifest_version: z.literal("1.0.0"),
  published_at: z.iso.datetime({ offset: true }),
  activity_order: z.array(z.enum(ACTIVITY_IDS)).length(ACTIVITY_IDS.length),
  packages: z.array(ContentManifestEntryV1Schema).length(ACTIVITY_IDS.length),
});
