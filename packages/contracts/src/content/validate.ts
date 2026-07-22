import type { z } from "zod";

import { ACTIVITY_GENERATOR_IDS, ACTIVITY_IDS } from "./ids.js";
import { contentChecksum } from "./checksum.js";
import { GeneratorRegistry } from "./generation/registry.js";
import { verifyGeneratedAnswer } from "./generation/independent_verify.js";
import {
  ActivityPackageDraftV1Schema,
  ActivityPackageV1Schema,
  ContentManifestV1Schema,
} from "./schema.js";
import type {
  ActivityPackageDraftV1,
  ActivityPackageV1,
  AnswerValueV1,
  ContentManifestV1,
  QuestionInstanceV1,
  ResolvedParametersV1,
  ValidationIssue,
  ValidationReport,
} from "./types.js";

const BAND_IDS = ["intro", "practice", "challenge"] as const;
const VALIDATION_SEEDS = [1, 7, 42, 20260721] as const;
const SAFE_TUNING_KEY = /^[a-z][a-z0-9_]{0,63}$/;
const SAFE_TUNING_VALUE = /^[a-z][a-z0-9_]{0,63}$/;
const SAFE_OPERATOR_VALUES = new Set(["+", "-", "*", "/", "%"]);
const FORBIDDEN_OBJECT_KEYS = new Set(["__proto__", "prototype", "constructor"]);
const GENERATOR_ANSWER_LAYOUT_IDS = {
  common_multiple_v1: "numeric_keypad",
  prime_factorization_v1: "factor_slots",
} as const;
const GENERATOR_REGISTRY = new GeneratorRegistry();

export type ContentPackageCollection =
  | readonly unknown[]
  | ReadonlyMap<string, unknown>
  | Readonly<Record<string, unknown>>;

export function validateActivityDraft(value: unknown): ValidationReport {
  const issues = findForbiddenObjectKeys(value);
  const unicodeIssues = findInvalidUnicode(value);
  issues.push(...unicodeIssues);
  if (unicodeIssues.length > 0) {
    return report(issues);
  }
  const parsed = ActivityPackageDraftV1Schema.safeParse(value);
  if (!parsed.success) {
    issues.push(...zodIssues(parsed.error.issues));
    return report(issues);
  }

  const samples = validateDraftSemantics(parsed.data as ActivityPackageDraftV1, issues);
  return report(issues, samples);
}

export function validatePublishedActivity(value: unknown): ValidationReport {
  const issues = findForbiddenObjectKeys(value);
  const unicodeIssues = findInvalidUnicode(value);
  issues.push(...unicodeIssues);
  if (unicodeIssues.length > 0) {
    return report(issues);
  }
  const parsed = ActivityPackageV1Schema.safeParse(value);
  if (!parsed.success) {
    issues.push(...zodIssues(parsed.error.issues));
    return report(issues);
  }

  const published = parsed.data as ActivityPackageV1;
  const samples = validateDraftSemantics(published, issues);
  if (published.checksum !== contentChecksum(published)) {
    issues.push({
      code: "CHECKSUM_MISMATCH",
      path: ["checksum"],
      message: "Package checksum does not cover the canonical authored fields",
    });
  }
  return report(issues, samples);
}

export function validateContentManifest(
  value: unknown,
  packages: ContentPackageCollection,
): ValidationReport {
  const issues = findForbiddenObjectKeys(value);
  const unicodeIssues = findInvalidUnicode(value);
  issues.push(...unicodeIssues);
  if (unicodeIssues.length > 0) {
    return report(issues);
  }
  const parsed = ContentManifestV1Schema.safeParse(value);
  if (!parsed.success) {
    issues.push(...zodIssues(parsed.error.issues));
    return report(issues);
  }

  const manifest = parsed.data as ContentManifestV1;
  validateManifestCatalogue(manifest, issues);

  const packageCount = collectionSize(packages);
  if (packageCount !== ACTIVITY_IDS.length) {
    issues.push({
      code: "PACKAGE_SET_SIZE",
      path: ["packages"],
      message: `Expected exactly ${ACTIVITY_IDS.length} parsed packages, received ${packageCount}`,
    });
  }

  manifest.packages.forEach((entry, index) => {
    const expectedPath = packagePath(entry.activity_id, entry.content_version);
    if (entry.path !== expectedPath) {
      issues.push({
        code: "MANIFEST_PACKAGE_PATH",
        path: ["packages", index, "path"],
        message: `Package path must be ${expectedPath}`,
      });
    }

    const candidate = findPackage(packages, entry.path, entry.activity_id, entry.content_version);
    if (candidate === undefined) {
      issues.push({
        code: "MANIFEST_PACKAGE_MISSING",
        path: ["packages", index],
        message: `No parsed package was supplied for ${entry.activity_id}@${entry.content_version}`,
      });
      return;
    }

    const packageReport = validatePublishedActivity(candidate);
    issues.push(
      ...packageReport.issues.map((issue) => ({
        ...issue,
        path: ["packages", index, "package", ...issue.path],
      })),
    );

    const identity = readPackageIdentity(candidate);
    if (
      identity === undefined ||
      identity.activity_id !== entry.activity_id ||
      identity.content_version !== entry.content_version
    ) {
      issues.push({
        code: "MANIFEST_PACKAGE_IDENTITY",
        path: ["packages", index],
        message: "Manifest entry and parsed package identity differ",
      });
    }
    if (identity?.checksum !== entry.checksum) {
      issues.push({
        code: "MANIFEST_CHECKSUM_MISMATCH",
        path: ["packages", index, "checksum"],
        message: "Manifest checksum and parsed package checksum differ",
      });
    }
  });

  return report(issues);
}

function validateDraftSemantics(
  draft: ActivityPackageDraftV1,
  issues: ValidationIssue[],
): QuestionInstanceV1[] {
  const samples: QuestionInstanceV1[] = [];
  if (draft.icon_id !== draft.activity_id) {
    issues.push({
      code: "ICON_ACTIVITY_MISMATCH",
      path: ["icon_id"],
      message: "An activity package must use its allowlisted activity icon",
    });
  }

  const expectedGenerator = ACTIVITY_GENERATOR_IDS[draft.activity_id];
  draft.difficulty_bands.forEach((band, index) => {
    if (band.generator_id !== expectedGenerator) {
      issues.push({
        code: "GENERATOR_ACTIVITY_MISMATCH",
        path: ["difficulty_bands", index, "generator_id"],
        message: `${draft.activity_id} requires generator ${expectedGenerator}`,
      });
    }
    const requiredLayout =
      GENERATOR_ANSWER_LAYOUT_IDS[
        band.generator_id as keyof typeof GENERATOR_ANSWER_LAYOUT_IDS
      ];
    if (requiredLayout !== undefined && band.answer_layout.id !== requiredLayout) {
      issues.push({
        code: "ANSWER_LAYOUT_GENERATOR_MISMATCH",
        path: ["difficulty_bands", index, "answer_layout", "id"],
        message: `${band.generator_id} requires answer layout ${requiredLayout}`,
      });
    }
    validateTuningParameters(
      band.generator_parameters,
      ["difficulty_bands", index, "generator_parameters"],
      issues,
    );
    if (band.answer_layout.options !== undefined) {
      validateTuningParameters(
        band.answer_layout.options,
        ["difficulty_bands", index, "answer_layout", "options"],
        issues,
      );
    }
    validateTuningParameters(
      band.manipulative.config,
      ["difficulty_bands", index, "manipulative", "config"],
      issues,
    );
    validateTuningParameters(
      band.manipulative.initial_state,
      ["difficulty_bands", index, "manipulative", "initial_state"],
      issues,
    );
    validateGeneratorSamples(draft, band, index, issues, samples);
  });

  const [comboOne, comboTwo, comboThree] = draft.run.combo_thresholds;
  if (!(comboOne < comboTwo && comboTwo < comboThree)) {
    issues.push({
      code: "COMBO_THRESHOLDS",
      path: ["run", "combo_thresholds"],
      message: "Combo thresholds must be unique and strictly increasing",
    });
  }

  if (draft.adaptive_policy !== undefined) {
    const minimum = BAND_IDS.indexOf(draft.adaptive_policy.min_band_id as (typeof BAND_IDS)[number]);
    const maximum = BAND_IDS.indexOf(draft.adaptive_policy.max_band_id as (typeof BAND_IDS)[number]);
    if (minimum === -1 || maximum === -1 || minimum > maximum) {
      issues.push({
        code: "ADAPTIVE_BOUNDS",
        path: ["adaptive_policy"],
        message: "Adaptive minimum and maximum must reference ordered published bands",
      });
    }
    if (draft.adaptive_policy.demote_correctness >= draft.adaptive_policy.promote_correctness) {
      issues.push({
        code: "ADAPTIVE_THRESHOLDS",
        path: ["adaptive_policy"],
        message: "Demotion correctness must be below promotion correctness",
      });
    }
  }

  const expectedSamples = new Set(
    BAND_IDS.flatMap((bandId) => VALIDATION_SEEDS.map((seed) => `${bandId}:${seed}`)),
  );
  const actualSamples = draft.validation_samples.map((sample) => `${sample.band_id}:${sample.seed}`);
  const actualSampleSet = new Set(actualSamples);
  if (
    actualSamples.length !== expectedSamples.size ||
    actualSampleSet.size !== expectedSamples.size ||
    [...expectedSamples].some((key) => !actualSampleSet.has(key))
  ) {
    issues.push({
      code: "VALIDATION_SAMPLES",
      path: ["validation_samples"],
      message: "Each band requires one validation sample for seeds 1, 7, 42, and 20260721",
    });
  }
  return samples;
}

function validateGeneratorSamples(
  draft: ActivityPackageDraftV1,
  band: ActivityPackageDraftV1["difficulty_bands"][number],
  bandIndex: number,
  issues: ValidationIssue[],
  samples: QuestionInstanceV1[],
): void {
  const generator = GENERATOR_REGISTRY.create(band.generator_id);
  if (generator === null) return;

  const parameterReport = generator.validateParameters(band.generator_parameters);
  if (!parameterReport.valid) {
    issues.push({
      code: "GENERATOR_PARAMETERS_INVALID",
      path: ["difficulty_bands", bandIndex, "generator_parameters"],
      message: `Runtime generator rejected parameters: ${parameterReport.issues.join(", ")}`,
    });
    return;
  }

  const activityInput = draft as unknown as Readonly<Record<string, unknown>>;
  const bandInput = band as unknown as Readonly<Record<string, unknown>>;
  for (const seed of VALIDATION_SEEDS) {
    const authoredSampleIndex = draft.validation_samples.findIndex(
      (candidate) => candidate.band_id === band.band_id && candidate.seed === seed,
    );
    const samplePath: (string | number)[] = authoredSampleIndex === -1
      ? ["difficulty_bands", bandIndex]
      : ["validation_samples", authoredSampleIndex];
    let generated: ReturnType<typeof generator.generate>;
    try {
      generated = generator.generate(activityInput, bandInput, seed);
    } catch {
      generated = null;
    }
    if (generated === null) {
      issues.push({
        code: "GENERATOR_SAMPLE_FAILED",
        path: samplePath,
        message: `Runtime generator failed for seed ${seed}: ${generator.lastError || "UNEXPECTED_ERROR"}`,
      });
      continue;
    }

    const question: QuestionInstanceV1 = {
      contract_version: 1,
      activity_id: draft.activity_id,
      content_version: draft.content_version,
      generator_id: band.generator_id,
      band_id: band.band_id,
      seed,
      resolved_parameters: structuredClone(generated.resolved_parameters),
      prompt: structuredClone(generated.prompt),
      correct_answer: structuredClone(generated.correct_answer),
      answer_layout: structuredClone(band.answer_layout),
      manipulative: structuredClone(band.manipulative),
    };
    samples.push(question);

    const independentIssues = verifyGeneratedAnswer(
      band.generator_id,
      generated.resolved_parameters,
      generated.correct_answer,
    );
    if (independentIssues.length > 0) {
      issues.push({
        code: "GENERATOR_ANSWER_INVALID",
        path: samplePath,
        message: `Independent answer verification failed for seed ${seed}: ${independentIssues.join(", ")}`,
      });
    }

    const authored = authoredSampleIndex === -1
      ? undefined
      : draft.validation_samples[authoredSampleIndex];
    if (authored !== undefined && !answersEqual(generated.correct_answer, authored.expected_answer)) {
      issues.push({
        code: "VALIDATION_SAMPLE_ANSWER_MISMATCH",
        path: ["validation_samples", authoredSampleIndex, "expected_answer"],
        message: `Authored validation answer differs from runtime output for seed ${seed}`,
      });
    }
  }
}

function answersEqual(left: AnswerValueV1, right: AnswerValueV1): boolean {
  if (left.kind !== right.kind) return false;
  if (left.kind === "integer" && right.kind === "integer") {
    return left.value === right.value;
  }
  if (left.kind === "integer_list" && right.kind === "integer_list") {
    return left.order_matters === right.order_matters &&
      left.values.length === right.values.length &&
      left.values.every((value, index) => value === right.values[index]);
  }
  return false;
}

function validateManifestCatalogue(manifest: ContentManifestV1, issues: ValidationIssue[]): void {
  if (!sameOrderedValues(manifest.activity_order, ACTIVITY_IDS)) {
    issues.push({
      code: "MANIFEST_ACTIVITY_ORDER",
      path: ["activity_order"],
      message: "Manifest activity_order must match the complete 1.0 catalogue",
    });
  }

  const entryActivities = manifest.packages.map((entry) => entry.activity_id);
  const entrySet = new Set(entryActivities);
  if (
    entrySet.size !== ACTIVITY_IDS.length ||
    ACTIVITY_IDS.some((activityId) => !entrySet.has(activityId))
  ) {
    issues.push({
      code: "MANIFEST_ACTIVITY_SET",
      path: ["packages"],
      message: "Manifest packages must contain every allowlisted activity exactly once",
    });
  }
  if (!sameOrderedValues(entryActivities, ACTIVITY_IDS)) {
    issues.push({
      code: "MANIFEST_PACKAGE_ORDER",
      path: ["packages"],
      message: "Manifest packages must follow the canonical activity order",
    });
  }

  const paths = manifest.packages.map((entry) => entry.path);
  if (new Set(paths).size !== paths.length) {
    issues.push({
      code: "MANIFEST_DUPLICATE_PATH",
      path: ["packages"],
      message: "Manifest package paths must be unique",
    });
  }
}

function validateTuningParameters(
  parameters: ResolvedParametersV1,
  path: (string | number)[],
  issues: ValidationIssue[],
): void {
  for (const [key, value] of Object.entries(parameters)) {
    if (!SAFE_TUNING_KEY.test(key) || FORBIDDEN_OBJECT_KEYS.has(key)) {
      issues.push({
        code: "UNSAFE_TUNING_KEY",
        path: [...path, key],
        message: "Tuning keys must be short lowercase identifiers",
      });
    }
    if (
      typeof value === "string" &&
      !SAFE_TUNING_VALUE.test(value) &&
      !SAFE_OPERATOR_VALUES.has(value)
    ) {
      issues.push({
        code: "UNSAFE_TUNING_STRING",
        path: [...path, key],
        message: "Tuning strings must be registered identifiers, never paths, URLs, or code",
      });
    }
  }
}

function findForbiddenObjectKeys(value: unknown): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const ancestors = new Set<object>();

  function visit(current: unknown, path: (string | number)[]): void {
    if (current === null || typeof current !== "object" || ancestors.has(current)) {
      return;
    }
    ancestors.add(current);
    try {
      for (const key of Reflect.ownKeys(current)) {
        if (typeof key === "symbol") {
          issues.push({
            code: "FORBIDDEN_OBJECT_KEY",
            path,
            message: "Symbol keys are not valid content fields",
          });
          continue;
        }
        if (FORBIDDEN_OBJECT_KEYS.has(key)) {
          issues.push({
            code: "FORBIDDEN_OBJECT_KEY",
            path: [...path, key],
            message: `Reserved object key is forbidden: ${key}`,
          });
        }
        const descriptor = Object.getOwnPropertyDescriptor(current, key);
        if (descriptor !== undefined && "value" in descriptor) {
          const childPath = Array.isArray(current) && key !== "length" ? Number(key) : key;
          if (childPath !== "length") {
            visit(descriptor.value, [...path, childPath]);
          }
        }
      }
    } finally {
      ancestors.delete(current);
    }
  }

  visit(value, []);
  return issues;
}

function findInvalidUnicode(value: unknown): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const ancestors = new Set<object>();

  function addIssue(path: (string | number)[]): void {
    issues.push({
      code: "INVALID_UNICODE",
      path,
      message: "Content strings and object keys must not contain U+0000 or lossy Unicode",
    });
  }

  function visit(current: unknown, path: (string | number)[]): void {
    if (typeof current === "string") {
      if (!isLosslessUnicode(current)) {
        addIssue(path);
      }
      return;
    }
    if (current === null || typeof current !== "object" || ancestors.has(current)) {
      return;
    }

    ancestors.add(current);
    try {
      for (const key of Reflect.ownKeys(current)) {
        if (typeof key === "symbol" || (Array.isArray(current) && key === "length")) {
          continue;
        }
        const childPath =
          Array.isArray(current) && /^(?:0|[1-9][0-9]*)$/.test(key) ? Number(key) : key;
        const pathWithKey = [...path, childPath];
        if (!Array.isArray(current) && !isLosslessUnicode(key)) {
          addIssue(pathWithKey);
        }
        const descriptor = Object.getOwnPropertyDescriptor(current, key);
        if (descriptor !== undefined && "value" in descriptor) {
          visit(descriptor.value, pathWithKey);
        }
      }
    } finally {
      ancestors.delete(current);
    }
  }

  visit(value, []);
  return issues;
}

function isLosslessUnicode(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const codeUnit = value.charCodeAt(index);
    if (codeUnit === 0 || codeUnit === 0xfffd) {
      return false;
    }
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      const lowCodeUnit = value.charCodeAt(index + 1);
      if (!(lowCodeUnit >= 0xdc00 && lowCodeUnit <= 0xdfff)) {
        return false;
      }
      index += 1;
      continue;
    }
    if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

function zodIssues(issues: z.core.$ZodIssue[]): ValidationIssue[] {
  return issues.map((issue) => ({
    code: `SCHEMA_${issue.code.toUpperCase()}`,
    path: issue.path.map((segment) => (typeof segment === "symbol" ? String(segment) : segment)),
    message: issue.message,
  }));
}

function report(
  issues: ValidationIssue[],
  samples: QuestionInstanceV1[] = [],
): ValidationReport {
  return { valid: issues.length === 0, issues, samples };
}

function collectionSize(packages: ContentPackageCollection): number {
  if (Array.isArray(packages)) {
    return packages.length;
  }
  if (packages instanceof Map) {
    return packages.size;
  }
  return Object.keys(packages).length;
}

function findPackage(
  packages: ContentPackageCollection,
  path: string,
  activityId: string,
  contentVersion: string,
): unknown {
  if (Array.isArray(packages)) {
    return packages.find((candidate) => {
      const identity = readPackageIdentity(candidate);
      return identity?.activity_id === activityId && identity.content_version === contentVersion;
    });
  }
  if (packages instanceof Map) {
    return packages.get(path);
  }
  const byPath = packages as Readonly<Record<string, unknown>>;
  return Object.hasOwn(byPath, path) ? byPath[path] : undefined;
}

function readPackageIdentity(value: unknown):
  | { activity_id: unknown; content_version: unknown; checksum: unknown }
  | undefined {
  if (value === null || typeof value !== "object") {
    return undefined;
  }
  const record = value as Record<string, unknown>;
  return {
    activity_id: record.activity_id,
    content_version: record.content_version,
    checksum: record.checksum,
  };
}

function packagePath(activityId: string, contentVersion: string): string {
  return `content/packages/${activityId}/${contentVersion}.json`;
}

function sameOrderedValues(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
