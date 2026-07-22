export const ACTIVITY_IDS = [
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
] as const;

export const GENERATOR_IDS = [
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
] as const;

export const ACTIVITY_GENERATOR_IDS = {
  addition_ones: "addition_v1",
  subtraction_ones: "subtraction_v1",
  multiplication: "multiplication_v1",
  common_multiples_lcm: "common_multiple_v1",
  prime_factorization: "prime_factorization_v1",
  foundations_counting: "counting_v1",
  foundations_number_bonds: "number_bonds_v1",
  foundations_ten_frame: "ten_frame_v1",
  foundations_base_ten: "base_ten_v1",
  foundations_number_line: "number_line_v1",
  foundations_basic_operations: "basic_operations_v1",
} as const satisfies Record<(typeof ACTIVITY_IDS)[number], (typeof GENERATOR_IDS)[number]>;

export const MANIPULATIVE_IDS = [
  "none",
  "counters",
  "ten_frame",
  "base_ten",
  "number_line",
  "answer_slots",
] as const;

export const ANSWER_LAYOUT_IDS = [
  "numeric_keypad",
  "choice_grid",
  "factor_slots",
  "manipulative_submit",
] as const;

export const SCENE_IDS = ["activity_run"] as const;

export const EFFECT_PRESET_IDS = [
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
] as const;

export const ICON_IDS = [
  ...ACTIVITY_IDS,
  "correct",
  "wrong",
  "heart",
  "speaker",
] as const;

export const DIALOGUE_IDS = [
  "moa_home_welcome",
  "moa_tutorial_counting",
  "moa_tutorial_number_bonds",
  "moa_tutorial_ten_frame",
  "moa_tutorial_base_ten",
  "moa_tutorial_number_line",
  "moa_tutorial_basic_operations",
  "moa_reward",
  "moa_level_up",
] as const;

export type ActivityId = (typeof ACTIVITY_IDS)[number];
export type GeneratorId = (typeof GENERATOR_IDS)[number];
export type ManipulativeId = (typeof MANIPULATIVE_IDS)[number];
export type AnswerLayoutId = (typeof ANSWER_LAYOUT_IDS)[number];
export type SceneId = (typeof SCENE_IDS)[number];
export type EffectPresetId = (typeof EFFECT_PRESET_IDS)[number];
export type IconId = (typeof ICON_IDS)[number];
export type DialogueId = (typeof DIALOGUE_IDS)[number];
