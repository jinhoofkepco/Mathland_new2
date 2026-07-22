import { createHash } from "node:crypto";

import {
  GeneratorRegistry,
  evaluateExpression,
  parseExpressionTokens,
  tokenizeExpression,
  validateActivityDraft,
  type ActivityId,
  type ActivityPackageDraftV1,
  type DifficultyBandV1,
  type ExpressionNode,
  type GeneratorId,
  type ResolvedParametersV1,
} from "../../../packages/contracts/src/index.js";
import { parseLegacyCsv } from "./parse_legacy_csv.js";
import type {
  LegacyCompatibilityAssertion,
  LegacyConversionResult,
  LegacyDocument,
  LegacyField,
  LegacyLevel,
} from "./legacy_types.js";

export const LEGACY_SOURCE_COMMIT = "08b9e7589a335f0c5674cfac6743132f8c4870f2";

const VALIDATION_SEEDS = [1, 7, 42, 20260721] as const;
const BAND_IDS = ["intro", "practice", "challenge"] as const;
const MAX_ENUMERATED_ASSIGNMENTS = 100_000;

interface SourceSpec {
  activity_id: ActivityId;
  generator_id: GeneratorId;
  sha256: string;
}

const SOURCE_SPECS: Readonly<Record<string, SourceSpec>> = {
  "quiz_game_11.csv": {
    activity_id: "addition_ones",
    generator_id: "addition_v1",
    sha256: "2bc0680a92758d1038854574f7f1f0dafe8ea17f5504990bd91e39b54de08329",
  },
  "quiz_game_7.csv": {
    activity_id: "subtraction_ones",
    generator_id: "subtraction_v1",
    sha256: "332afe72a2ede14f8cbc7e6659ca5028bafac368567b9550afb2a884041f1308",
  },
  "quiz_game_4.csv": {
    activity_id: "multiplication",
    generator_id: "multiplication_v1",
    sha256: "c6988f44a219ae324fc7d532ab8aafe1d360ee834888e945bfec07b2a4cbdc8c",
  },
  "quiz_game_9.csv": {
    activity_id: "common_multiples_lcm",
    generator_id: "common_multiple_v1",
    sha256: "d5e83eca772cfd3c6657702e3432fb7e807e46b29ddc198b201988938671bdc4",
  },
  "quiz_game_8_1.csv": {
    activity_id: "prime_factorization",
    generator_id: "prime_factorization_v1",
    sha256: "b5fbfd500cc7b309bc9ddd15700714135d41693505adc93e4e20c0412b8e1a2b",
  },
};

function requireSourceSpec(sourceName: string): SourceSpec {
  const spec = SOURCE_SPECS[sourceName];
  if (spec === undefined) throw new Error(`Unpinned legacy source ${sourceName}`);
  return spec;
}

function verifySourceHash(text: string, sourceName: string, spec: SourceSpec): void {
  const actual = createHash("sha256").update(text, "utf8").digest("hex");
  if (actual !== spec.sha256) {
    throw new Error(`Legacy source ${sourceName} does not match ${LEGACY_SOURCE_COMMIT}: ${actual}`);
  }
}

function metadataValue(document: LegacyDocument, key: string): string {
  const candidate = document.metadata.find((field) => field.key === key);
  if (candidate === undefined || candidate.cells.length !== 1) {
    throw new Error(`${document.source_name} is missing ${key} metadata`);
  }
  return candidate.cells[0]!;
}

function normalizeLegacyText(source: string): string {
  const expanded = source.split("[enter]").join(" ");
  let output = "";
  let pendingSpace = false;
  for (const character of expanded) {
    const whitespace = character === " " || character === "\t" || character === "\r" || character === "\n";
    if (whitespace) {
      pendingSpace = output.length > 0;
    } else {
      if (pendingSpace) output += " ";
      output += character;
      pendingSpace = false;
    }
  }
  return output;
}

function requireLevel(document: LegacyDocument, levelNumber: number): LegacyLevel {
  const level = document.levels.find((candidate) => candidate.level === levelNumber);
  if (level === undefined) throw new Error(`${document.source_name} is missing level ${levelNumber}`);
  return level;
}

function effectiveField(level: LegacyLevel, key: string, subLevel: number): LegacyField | null {
  const candidates = level.fields.filter((field) => field.key === key);
  const ranged = candidates.find(
    (field) =>
      field.range !== null &&
      field.range.minimum <= subLevel &&
      subLevel <= field.range.maximum,
  );
  if (ranged !== undefined) return ranged;
  return candidates.find((field) => field.range === null) ?? null;
}

function requireEffectiveField(level: LegacyLevel, key: string, subLevel: number): LegacyField {
  const candidate = effectiveField(level, key, subLevel);
  if (candidate === null) {
    throw new Error(`Legacy level ${level.level} has no ${key} at sub-level ${subLevel}`);
  }
  return candidate;
}

function requireIntegerValues(field: LegacyField): number[] {
  if (field.integer_values === null || field.integer_values.length === 0) {
    throw new Error(`Legacy field ${field.key} on line ${field.line} has no integer values`);
  }
  return field.integer_values;
}

function uniqueSorted(values: readonly number[]): number[] {
  return [...new Set(values)].sort((left, right) => left - right);
}

function allEffectiveComponentFields(level: LegacyLevel, subLevel: number): LegacyField[] {
  const keys = uniqueStrings(
    level.fields.filter((field) => field.key.startsWith("component ")).map((field) => field.key),
  );
  return keys
    .map((key) => effectiveField(level, key, subLevel))
    .filter((field): field is LegacyField => field !== null);
}

function uniqueStrings(values: readonly string[]): string[] {
  return [...new Set(values)].sort();
}

function numericComponentBounds(level: LegacyLevel, subLevel: number): { minimum: number; maximum: number } {
  const values = allEffectiveComponentFields(level, subLevel).flatMap((field) =>
    field.integer_values ?? [],
  );
  if (values.length === 0) throw new Error(`Legacy level ${level.level} has no numeric components`);
  return { minimum: Math.min(...values), maximum: Math.max(...values) };
}

function countLiteral(tokens: NonNullable<LegacyField["question_tokens"]>, literal: string): number {
  return tokens.filter((token) => token.kind === "literal" && token.value === literal).length;
}

function componentCountBefore(
  tokens: NonNullable<LegacyField["question_tokens"]>,
  literal: string,
): number {
  let count = 0;
  for (const token of tokens) {
    if (token.kind === "literal" && token.value === literal) return count;
    if (token.kind === "component") count += 1;
  }
  throw new Error(`Legacy question format does not contain ${literal}`);
}

function requireQuestionTokens(level: LegacyLevel, subLevel: number) {
  const field = requireEffectiveField(level, "question format", subLevel);
  if (field.question_tokens === null) throw new Error(`Legacy question format on line ${field.line} was not parsed`);
  return field.question_tokens;
}

function makeBand(
  bandId: (typeof BAND_IDS)[number],
  generatorId: GeneratorId,
  parameters: ResolvedParametersV1,
): DifficultyBandV1 {
  return {
    band_id: bandId,
    generator_id: generatorId,
    generator_parameters: parameters,
    answer_layout: {
      id: generatorId === "prime_factorization_v1" ? "factor_slots" : "numeric_keypad",
    },
    manipulative: { id: "none", config: {}, initial_state: {} },
  };
}

function additionBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  const level = requireLevel(document, 1);
  const points = [1, 21, 61] as const;
  return points.map((subLevel, index) => {
    const tokens = requireQuestionTokens(level, subLevel);
    const bounds = numericComponentBounds(level, subLevel);
    return makeBand(BAND_IDS[index]!, spec.generator_id, {
      operand_count: countLiteral(tokens, "+") + 1,
      operand_min: bounds.minimum,
      operand_max: bounds.maximum,
      place_mode: "ones_digit",
      carry: "allow",
    });
  }) as ActivityPackageDraftV1["difficulty_bands"];
}

function subtractionBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  const selected = [requireLevel(document, 1), requireLevel(document, 3), requireLevel(document, 4)] as const;
  return selected.map((level, index) => {
    if (index === 0) {
      const bounds = numericComponentBounds(level, 1);
      return makeBand(BAND_IDS[index]!, spec.generator_id, {
        operand_count: 2,
        operand_min: bounds.minimum,
        operand_max: bounds.maximum,
        place_mode: "ones_digit",
        borrow: "forbid",
        allow_negative: false,
      });
    }
    const digitCount = componentCountBefore(requireQuestionTokens(level, 1), "-");
    if (digitCount < 2 || digitCount > 6) throw new Error(`Unsupported subtraction width ${digitCount}`);
    return makeBand(BAND_IDS[index]!, spec.generator_id, {
      operand_count: 2,
      operand_min: 10 ** (digitCount - 1),
      operand_max: 10 ** digitCount - 1,
      place_mode: "full",
      borrow: "allow",
      allow_negative: false,
    });
  }) as ActivityPackageDraftV1["difficulty_bands"];
}

function composedDecimalBounds(
  level: LegacyLevel,
  tensComponent: string,
  onesComponent: string,
  subLevel: number,
): { minimum: number; maximum: number } {
  const tens = requireIntegerValues(requireEffectiveField(level, `component ${tensComponent}`, subLevel));
  const ones = requireIntegerValues(requireEffectiveField(level, `component ${onesComponent}`, subLevel));
  const values = tens.flatMap((left) => ones.map((right) => left * 10 + right));
  return { minimum: Math.min(...values), maximum: Math.max(...values) };
}

function multiplicationBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  const level = requireLevel(document, 1);
  const points = [1, 11, 61] as const;
  return points.map((subLevel, index) => {
    const left = composedDecimalBounds(level, "A", "B", subLevel);
    const right = composedDecimalBounds(level, "C", "D", subLevel);
    return makeBand(BAND_IDS[index]!, spec.generator_id, {
      left_min: left.minimum,
      left_max: left.maximum,
      right_min: right.minimum,
      right_max: right.maximum,
      display: "column",
    });
  }) as ActivityPackageDraftV1["difficulty_bands"];
}

function collectExpressionVariables(node: ExpressionNode, output: Set<string>): void {
  switch (node.kind) {
    case "integer":
      return;
    case "variable":
      output.add(node.name);
      return;
    case "unary":
      collectExpressionVariables(node.operand, output);
      return;
    case "binary":
      collectExpressionVariables(node.left, output);
      collectExpressionVariables(node.right, output);
      return;
    case "call":
      for (const argument of node.arguments) collectExpressionVariables(argument, output);
  }
}

function expressionVariables(source: string): string[] {
  const tokenized = tokenizeExpression(source);
  if (!tokenized.ok) throw new Error(`Invalid canonical legacy expression ${source}`);
  const parsed = parseExpressionTokens(tokenized.tokens);
  if (!parsed.ok) throw new Error(`Invalid canonical legacy expression ${source}`);
  const variables = new Set<string>();
  collectExpressionVariables(parsed.expression, variables);
  return [...variables].sort();
}

function enumerateExpression(
  expression: string,
  pools: Readonly<Record<string, readonly number[]>>,
): number[] {
  const variables = expressionVariables(expression);
  let assignments: Record<string, number>[] = [{}];
  for (const variable of variables) {
    const values = pools[variable];
    if (values === undefined || values.length === 0) throw new Error(`No values for legacy variable ${variable}`);
    if (assignments.length * values.length > MAX_ENUMERATED_ASSIGNMENTS) {
      throw new Error("Legacy compatibility expression has too many assignments");
    }
    assignments = assignments.flatMap((assignment) =>
      values.map((value) => ({ ...assignment, [variable]: value })),
    );
  }
  return uniqueSorted(
    assignments.map((variables_) => {
      const result = evaluateExpression(expression, variables_);
      if (!result.ok) throw new Error(`Legacy compatibility expression failed: ${result.error_code}`);
      return result.value;
    }),
  );
}

function componentValues(
  level: LegacyLevel,
  component: string,
  subLevel: number,
  cache: Map<string, number[]>,
): number[] {
  const cached = cache.get(component);
  if (cached !== undefined) return cached;
  const field = requireEffectiveField(level, `component ${component}`, subLevel);
  if (field.integer_values !== null) {
    const values = uniqueSorted(field.integer_values);
    cache.set(component, values);
    return values;
  }
  if (field.canonical_expression === null) throw new Error(`Component ${component} has no values`);
  const pools: Record<string, readonly number[]> = {};
  for (const dependency of expressionVariables(field.canonical_expression)) {
    if (dependency === "sub_level") pools[dependency] = [subLevel];
    else if (dependency === "answer") throw new Error("Legacy computed component depends on runtime answer");
    else pools[dependency] = componentValues(level, dependency, subLevel, cache);
  }
  const values = enumerateExpression(field.canonical_expression, pools);
  cache.set(component, values);
  return values;
}

function commonMultipleBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  return BAND_IDS.map((bandId, index) => {
    const level = requireLevel(document, index + 1);
    const answer = requireEffectiveField(level, "answer equation", 1).canonical_expression;
    if (answer === null) throw new Error(`LCM level ${level.level} has no answer expression`);
    const operands = expressionVariables(answer);
    const cache = new Map<string, number[]>();
    const values = operands.flatMap((component) => componentValues(level, component, 1, cache));
    return makeBand(bandId, spec.generator_id, {
      operand_count: operands.length,
      operand_min: Math.min(...values),
      operand_max: Math.max(...values),
      require_distinct: false,
    });
  }) as ActivityPackageDraftV1["difficulty_bands"];
}

function primeFactorizationBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  const level = requireLevel(document, 1);
  const points = [1, 21, 61] as const;
  return points.map((subLevel, index) => {
    const computed = requireEffectiveField(level, "component E", subLevel).canonical_expression;
    if (computed === null) throw new Error(`Prime-factorization sub-level ${subLevel} has no product expression`);
    const factors = expressionVariables(computed);
    const cache = new Map<string, number[]>();
    const pools: Record<string, readonly number[]> = {};
    for (const factor of factors) pools[factor] = componentValues(level, factor, subLevel, cache);
    const values = enumerateExpression(computed, pools);
    const allowedPrimes = uniqueSorted(factors.flatMap((factor) => [...pools[factor]!]));
    return makeBand(BAND_IDS[index]!, spec.generator_id, {
      value_min: Math.min(...values),
      value_max: Math.max(...values),
      factor_count_min: factors.length,
      factor_count_max: factors.length,
      allowed_primes: allowedPrimes,
    });
  }) as ActivityPackageDraftV1["difficulty_bands"];
}

function deriveBands(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1["difficulty_bands"] {
  switch (spec.activity_id) {
    case "addition_ones":
      return additionBands(document, spec);
    case "subtraction_ones":
      return subtractionBands(document, spec);
    case "multiplication":
      return multiplicationBands(document, spec);
    case "common_multiples_lcm":
      return commonMultipleBands(document, spec);
    case "prime_factorization":
      return primeFactorizationBands(document, spec);
    default:
      throw new Error(`Legacy conversion is not available for ${spec.activity_id}`);
  }
}

function evaluatedScalar(level: LegacyLevel, key: string, subLevel: number): number {
  const field = requireEffectiveField(level, key, subLevel);
  if (field.integer_values !== null) return field.integer_values[0]!;
  if (field.canonical_expression === null) throw new Error(`Legacy field ${key} has no scalar value`);
  const result = evaluateExpression(field.canonical_expression, { sub_level: subLevel });
  if (!result.ok || result.value < 1) throw new Error(`Legacy field ${key} is not a positive integer`);
  return result.value;
}

function buildValidationSamples(
  activityId: ActivityId,
  bands: ActivityPackageDraftV1["difficulty_bands"],
): ActivityPackageDraftV1["validation_samples"] {
  return bands.flatMap((band) => {
    const generator = new GeneratorRegistry().create(band.generator_id);
    if (generator === null) throw new Error(`Missing generator ${band.generator_id}`);
    const parameterReport = generator.validateParameters(band.generator_parameters);
    if (!parameterReport.valid) {
      throw new Error(`Invalid converted parameters for ${activityId}/${band.band_id}: ${parameterReport.issues.join(",")}`);
    }
    return VALIDATION_SEEDS.map((seed) => {
      const generated = generator.generate(
        { activity_id: activityId },
        { generator_parameters: band.generator_parameters },
        seed,
      );
      if (generated === null) {
        throw new Error(`Unsatisfiable converted parameters for ${activityId}/${band.band_id}/${seed}`);
      }
      return { band_id: band.band_id, seed, expected_answer: generated.correct_answer };
    });
  });
}

function buildDraft(document: LegacyDocument, spec: SourceSpec): ActivityPackageDraftV1 {
  const firstLevel = document.levels[0]!;
  const title = normalizeLegacyText(metadataValue(document, "title"));
  const descriptionField = requireEffectiveField(firstLevel, "description", 1);
  const description = normalizeLegacyText(descriptionField.cells[0]!);
  const target = evaluatedScalar(firstLevel, "target number", 1);
  const seconds = evaluatedScalar(firstLevel, "time for each quiz", 1);
  const apples = evaluatedScalar(firstLevel, "apples per quiz", 1);
  const difficultyBands = deriveBands(document, spec);

  const draft: ActivityPackageDraftV1 = {
    schema_version: 1,
    content_version: "1.0.0",
    activity_id: spec.activity_id,
    localizations: {
      "ko-KR": {
        title,
        description,
        tutorial_steps: [description],
      },
    },
    icon_id: spec.activity_id,
    scene_id: "activity_run",
    run: {
      starting_hearts: 3,
      goal: { kind: "correct_answers", target },
      timer: { enabled: true, seconds, profile_can_disable: true },
      rewards: {
        apples_per_correct: apples,
        completion_apples: Math.max(target, apples * 2),
      },
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
    difficulty_bands: difficultyBands,
    adaptive_policy: {
      enabled_by_default: false,
      min_band_id: "intro",
      max_band_id: "challenge",
      window_size: 5,
      promote_correctness: 0.8,
      demote_correctness: 0.4,
    },
    validation_samples: buildValidationSamples(spec.activity_id, difficultyBands),
  };

  const report = validateActivityDraft(draft);
  if (!report.valid) {
    throw new Error(`Converted legacy draft is invalid: ${report.issues.map((issue) => issue.code).join(",")}`);
  }
  return draft;
}

function compatibilityAssertions(document: LegacyDocument): LegacyCompatibilityAssertion[] {
  const assertions: LegacyCompatibilityAssertion[] = [];
  for (const level of document.levels) {
    for (const field of level.fields) {
      if (field.canonical_expression === null) continue;
      if (field.key !== "answer equation" && !field.computed) continue;
      assertions.push({
        level: level.level,
        range: field.range,
        source_field: field.key,
        canonical_expression: field.canonical_expression,
      });
    }
  }
  return assertions;
}

export function convertLegacyCsvWithEvidence(text: string, sourceName: string): LegacyConversionResult {
  const spec = requireSourceSpec(sourceName);
  verifySourceHash(text, sourceName, spec);
  const document = parseLegacyCsv(text, sourceName);
  return {
    draft: buildDraft(document, spec),
    compatibility_assertions: compatibilityAssertions(document),
  };
}

export function convertLegacyCsv(text: string, sourceName: string): ActivityPackageDraftV1 {
  return convertLegacyCsvWithEvidence(text, sourceName).draft;
}
