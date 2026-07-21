import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  GeneratorRegistry,
  type ActivityPackageDraftV1,
  validateActivityDraft,
} from "../../src/index.js";
import { verifyGeneratedAnswer } from "../../../../tools/content/independent_verify.js";

const ACTIVITY_IDS = [
  "foundations_counting",
  "foundations_number_bonds",
  "foundations_ten_frame",
  "foundations_base_ten",
  "foundations_number_line",
  "foundations_basic_operations",
] as const;
const EXPECTED_MANIPULATIVES = [
  "counters",
  "counters",
  "ten_frame",
  "base_ten",
  "number_line",
  "counters",
] as const;
const SEEDS = [1, 7, 42, 20260721] as const;

function loadSource(activityId: (typeof ACTIVITY_IDS)[number]): ActivityPackageDraftV1 {
  const url = new URL(`../../../../content/sources/${activityId}.json`, import.meta.url);
  return JSON.parse(readFileSync(url, "utf8")) as ActivityPackageDraftV1;
}

describe("seven-year-old foundations sources", () => {
  it.each(ACTIVITY_IDS.map((activityId, index) => [activityId, EXPECTED_MANIPULATIVES[index]] as const))(
    "validates %s with %s",
    (activityId, manipulativeId) => {
      const source = loadSource(activityId);
      expect(validateActivityDraft(source).issues).toEqual([]);
      expect(source.run.starting_hearts).toBe(3);
      expect(source.run.timer.enabled).toBe(false);
      expect(source.run.timer.profile_can_disable).toBe(true);
      expect(source.adaptive_policy?.enabled_by_default).toBe(false);
      expect(source.validation_samples).toHaveLength(12);
      expect(source.difficulty_bands.map((band) => band.band_id)).toEqual([
        "intro",
        "practice",
        "challenge",
      ]);
      expect(source.difficulty_bands.every((band) => band.manipulative.id === manipulativeId)).toBe(true);
      expect(source.difficulty_bands.every((band) => band.answer_layout.id === "manipulative_submit")).toBe(true);

      const registry = new GeneratorRegistry();
      const generatorActivity = source as unknown as Readonly<Record<string, unknown>>;
      for (const band of source.difficulty_bands) {
        const generatorBand = band as unknown as Readonly<Record<string, unknown>>;
        const generator = registry.create(band.generator_id);
        expect(generator?.validateParameters(band.generator_parameters).issues).toEqual([]);
        for (let seed = 1; seed <= 1000; seed += 1) {
          const generated = generator?.generate(generatorActivity, generatorBand, seed);
          expect(generated, `${activityId}/${band.band_id}/${seed}`).not.toBeNull();
          if (generated !== null && generated !== undefined) {
            expect(
              verifyGeneratedAnswer(band.generator_id, generated.resolved_parameters, generated.correct_answer),
            ).toEqual([]);
          }
        }
        for (const seed of SEEDS) {
          const sample = source.validation_samples.find(
            (candidate) => candidate.band_id === band.band_id && candidate.seed === seed,
          );
          expect(generator?.generate(generatorActivity, generatorBand, seed)?.correct_answer).toEqual(sample?.expected_answer);
        }
      }
    },
  );

  it("centralizes Korean prompts and action labels with exact interpolation arguments", () => {
    const localeUrl = new URL("../../../../content/locales/ko-KR.json", import.meta.url);
    const locale = JSON.parse(readFileSync(localeUrl, "utf8")) as Record<string, string>;
    for (const key of [
      "question.addition",
      "question.subtraction",
      "question.multiplication",
      "question.common_multiple",
      "question.prime_factorization",
      "question.counting",
      "question.number_bonds",
      "question.ten_frame",
      "question.base_ten",
      "question.number_line",
      "question.basic_operations",
      "manipulative.submit",
      "activity.speaker",
      "feedback.correct",
      "feedback.wrong",
    ]) {
      expect(locale[key], key).toBeTypeOf("string");
      expect(locale[key]?.trim(), key).not.toHaveLength(0);
    }
    expect(locale["question.addition"]?.match(/\{expression\}/g)).toHaveLength(1);
    expect(locale["question.number_bonds"]?.match(/\{whole\}|\{shown_part\}/g)).toHaveLength(2);
    expect(locale["question.number_line"]?.match(/\{start\}|\{step\}/g)).toHaveLength(2);
  });
});
