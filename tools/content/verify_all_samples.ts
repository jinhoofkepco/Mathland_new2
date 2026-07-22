import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ACTIVITY_IDS,
  GeneratorRegistry,
  canonicalJson,
  parseJsonStrict,
  validateActivityDraft,
  type ActivityPackageDraftV1,
} from "../../packages/contracts/src/index.js";

import { verifyGeneratedAnswer } from "./independent_verify.js";

export interface ContentSampleSummary {
  activities: number;
  bands: number;
  samples: number;
}

export function readActivitySources(rootDir: string): ActivityPackageDraftV1[] {
  const sourceDir = resolve(rootDir, "content", "sources");
  const discovered = readdirSync(sourceDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => entry.name)
    .sort();
  const expected = [...ACTIVITY_IDS].map((activityId) => `${activityId}.json`).sort();
  if (canonicalJson(discovered) !== canonicalJson(expected)) {
    throw new Error(`Content source catalogue mismatch: expected ${expected.join(", ")}; received ${discovered.join(", ")}`);
  }

  return ACTIVITY_IDS.map((activityId) => {
    const path = resolve(sourceDir, `${activityId}.json`);
    const value = parseJsonStrict(readFileSync(path, "utf8"));
    const report = validateActivityDraft(value);
    if (!report.valid) throw validationError(`Invalid activity source ${activityId}`, report.issues);
    const source = value as ActivityPackageDraftV1;
    if (source.activity_id !== activityId) {
      throw new Error(`Activity source ${activityId} declares ${source.activity_id}`);
    }
    return source;
  });
}

export function verifyAllSamples(
  unorderedSources: readonly ActivityPackageDraftV1[],
): ContentSampleSummary {
  const byId = new Map(unorderedSources.map((source) => [source.activity_id, source] as const));
  if (byId.size !== ACTIVITY_IDS.length || unorderedSources.length !== ACTIVITY_IDS.length) {
    throw new Error(`Expected exactly ${ACTIVITY_IDS.length} unique activity sources`);
  }

  const registry = new GeneratorRegistry();
  let bands = 0;
  let samples = 0;
  for (const activityId of ACTIVITY_IDS) {
    const sourceValue = byId.get(activityId);
    if (sourceValue === undefined) throw new Error(`Missing activity source ${activityId}`);
    const source = withoutChecksum(sourceValue);
    const report = validateActivityDraft(source);
    if (!report.valid) throw validationError(`Invalid activity source ${activityId}`, report.issues);
    const activityInput = source as unknown as Readonly<Record<string, unknown>>;
    const bandById = new Map(source.difficulty_bands.map((band) => [band.band_id, band] as const));
    bands += source.difficulty_bands.length;
    for (const sample of source.validation_samples) {
      const band = bandById.get(sample.band_id);
      if (band === undefined) {
        throw new Error(`${activityId}/${sample.band_id}/${sample.seed}: missing difficulty band`);
      }
      const generator = registry.create(band.generator_id);
      if (generator === null) {
        throw new Error(`${activityId}/${sample.band_id}/${sample.seed}: unknown generator ${band.generator_id}`);
      }
      const parameterReport = generator.validateParameters(band.generator_parameters);
      if (!parameterReport.valid) {
        throw new Error(
          `${activityId}/${sample.band_id}: invalid generator parameters: ${parameterReport.issues.join(", ")}`,
        );
      }
      const generated = generator.generate(
        activityInput,
        band as unknown as Readonly<Record<string, unknown>>,
        sample.seed,
      );
      if (generated === null) {
        throw new Error(
          `${activityId}/${sample.band_id}/${sample.seed}: generator failed (${generator.lastError})`,
        );
      }
      const independentIssues = verifyGeneratedAnswer(
        band.generator_id,
        generated.resolved_parameters,
        generated.correct_answer,
      );
      if (independentIssues.length > 0) {
        throw new Error(
          `${activityId}/${sample.band_id}/${sample.seed}: independent verification failed: ${independentIssues.join(", ")}; resolved=${canonicalJson(generated.resolved_parameters)}`,
        );
      }
      if (canonicalJson(generated.correct_answer) !== canonicalJson(sample.expected_answer)) {
        throw new Error(
          `${activityId}/${sample.band_id}/${sample.seed}: fixed answer mismatch; expected=${canonicalJson(sample.expected_answer)} actual=${canonicalJson(generated.correct_answer)}`,
        );
      }
      samples += 1;
    }
  }
  return { activities: ACTIVITY_IDS.length, bands, samples };
}

function withoutChecksum(source: ActivityPackageDraftV1): ActivityPackageDraftV1 {
  if (!("checksum" in source)) return source;
  const { checksum: _checksum, ...draft } = source as ActivityPackageDraftV1 & { checksum: unknown };
  return draft as ActivityPackageDraftV1;
}

function validationError(
  prefix: string,
  issues: readonly { code: string; path: readonly (string | number)[]; message: string }[],
): Error {
  return new Error(
    `${prefix}: ${issues.map((issue) => `${issue.code}@${issue.path.join(".")}: ${issue.message}`).join("; ")}`,
  );
}

function isDirectInvocation(): boolean {
  return process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isDirectInvocation()) {
  try {
    const rootDir = process.cwd();
    const summary = verifyAllSamples(readActivitySources(rootDir));
    process.stdout.write(
      `Verified ${summary.activities} activities, ${summary.bands} bands, ${summary.samples} samples\n`,
    );
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode = 1;
  }
}
