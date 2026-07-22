import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  GeneratorRegistry,
  type ActivityPackageDraftV1,
  validateActivityDraft,
} from "../../src/index.js";
import { verifyGeneratedAnswer } from "../../../../tools/content/independent_verify.js";

const ACTIVITY_IDS = [
  "addition_ones",
  "subtraction_ones",
  "multiplication",
  "common_multiples_lcm",
  "prime_factorization",
] as const;
const BAND_IDS = ["intro", "practice", "challenge"] as const;
const SEEDS = [1, 7, 42, 20260721] as const;

function loadSource(activityId: (typeof ACTIVITY_IDS)[number]): ActivityPackageDraftV1 {
  const url = new URL(`../../../../content/sources/${activityId}.json`, import.meta.url);
  return JSON.parse(readFileSync(url, "utf8")) as ActivityPackageDraftV1;
}

describe("migrated activity sources", () => {
  it.each(ACTIVITY_IDS)("validates and independently verifies %s", (activityId) => {
    const source = loadSource(activityId);
    expect(source.activity_id).toBe(activityId);
    expect(validateActivityDraft(source).issues).toEqual([]);
    expect(source.localizations["ko-KR"].title).not.toHaveLength(0);
    expect(source.localizations["ko-KR"].description).not.toHaveLength(0);
    expect(source.localizations["ko-KR"].tutorial_steps.length).toBeGreaterThan(0);
    expect(source.run.starting_hearts).toBe(3);
    expect(source.run.goal.target).toBeGreaterThanOrEqual(8);
    expect(source.run.timer.profile_can_disable).toBe(true);
    expect(source.run.combo_thresholds).toEqual([2, 4, 7]);
    expect(source.adaptive_policy?.enabled_by_default).toBe(false);
    expect(source.difficulty_bands.map((band) => band.band_id)).toEqual(BAND_IDS);
    expect(source.validation_samples).toHaveLength(12);

    const registry = new GeneratorRegistry();
    const generatorActivity = source as unknown as Readonly<Record<string, unknown>>;
    for (const band of source.difficulty_bands) {
      const generatorBand = band as unknown as Readonly<Record<string, unknown>>;
      const generator = registry.create(band.generator_id);
      expect(generator).not.toBeNull();
      expect(generator?.validateParameters(band.generator_parameters).issues).toEqual([]);
      for (let seed = 1; seed <= 1000; seed += 1) {
        const generated = generator?.generate(generatorActivity, generatorBand, seed);
        expect(generated, `${activityId}/${band.band_id}/${seed}`).not.toBeNull();
        if (generated !== null && generated !== undefined) {
          expect(
            verifyGeneratedAnswer(band.generator_id, generated.resolved_parameters, generated.correct_answer),
            `${activityId}/${band.band_id}/${seed}`,
          ).toEqual([]);
        }
      }
      for (const seed of SEEDS) {
        const generated = generator?.generate(generatorActivity, generatorBand, seed);
        const sample = source.validation_samples.find(
          (candidate) => candidate.band_id === band.band_id && candidate.seed === seed,
        );
        expect(sample).toBeDefined();
        expect(generated?.correct_answer).toEqual(sample?.expected_answer);
      }
    }
  });
});
