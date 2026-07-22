import type {
  ActivityId,
  AnswerLayoutId,
  EffectPresetId,
  GeneratorId,
  IconId,
  ManipulativeId,
  SceneId,
} from "./ids.js";

export type SemanticVersion = `${number}.${number}.${number}`;
export type Sha256Checksum = `sha256:${string}`;

export type AnswerValueV1 =
  | { kind: "integer"; value: number }
  | { kind: "integer_list"; values: number[]; order_matters: boolean };

export type ResolvedParameterValueV1 = boolean | number | string | number[];
export type ResolvedParametersV1 = Record<string, ResolvedParameterValueV1>;

export interface AnswerLayoutV1 {
  id: AnswerLayoutId;
  options?: ResolvedParametersV1;
}

export interface ManipulativeConfigV1 {
  id: ManipulativeId;
  config: ResolvedParametersV1;
  initial_state: ResolvedParametersV1;
}

export interface PromptV1 {
  key: string;
  args: Record<string, number | string>;
}

export interface QuestionInstanceV1 {
  contract_version: 1;
  activity_id: ActivityId;
  content_version: SemanticVersion;
  generator_id: GeneratorId;
  band_id: string;
  seed: number;
  resolved_parameters: ResolvedParametersV1;
  prompt: PromptV1;
  correct_answer: AnswerValueV1;
  answer_layout: AnswerLayoutV1;
  manipulative: ManipulativeConfigV1;
}

export interface DifficultyBandV1 {
  band_id: string;
  generator_id: GeneratorId;
  generator_parameters: ResolvedParametersV1;
  answer_layout: AnswerLayoutV1;
  manipulative: ManipulativeConfigV1;
}

export interface ActivityPackageDraftV1 {
  schema_version: 1;
  content_version: SemanticVersion;
  activity_id: ActivityId;
  localizations: Record<
    "ko-KR",
    {
      title: string;
      description: string;
      tutorial_steps: string[];
    }
  >;
  icon_id: IconId;
  scene_id: SceneId;
  run: {
    starting_hearts: number;
    goal: { kind: "correct_answers"; target: number };
    timer: { enabled: boolean; seconds: number; profile_can_disable: boolean };
    rewards: { apples_per_correct: number; completion_apples: number };
    combo_thresholds: [number, number, number];
    boss_every_correct: number;
    effects: {
      correct: EffectPresetId;
      wrong: EffectPresetId;
      combo: EffectPresetId;
      boss: EffectPresetId;
      level_up: EffectPresetId;
      reward: EffectPresetId;
      health_loss: EffectPresetId;
    };
  };
  difficulty_bands: DifficultyBandV1[];
  adaptive_policy?: {
    enabled_by_default: false;
    min_band_id: string;
    max_band_id: string;
    window_size: number;
    promote_correctness: number;
    demote_correctness: number;
  };
  validation_samples: {
    band_id: string;
    seed: number;
    expected_answer: AnswerValueV1;
  }[];
}

export interface ActivityPackageV1 extends ActivityPackageDraftV1 {
  checksum: Sha256Checksum;
}

export interface ContentManifestEntryV1 {
  activity_id: ActivityId;
  content_version: SemanticVersion;
  path: `content/packages/${ActivityId}/${SemanticVersion}.json`;
  checksum: Sha256Checksum;
}

export interface ContentManifestV1 {
  schema_version: 1;
  manifest_version: SemanticVersion;
  published_at: string;
  activity_order: ActivityId[];
  packages: ContentManifestEntryV1[];
}

export interface ValidationIssue {
  code: string;
  path: (string | number)[];
  message: string;
}

export interface ValidationReport {
  valid: boolean;
  issues: ValidationIssue[];
  samples: QuestionInstanceV1[];
}
