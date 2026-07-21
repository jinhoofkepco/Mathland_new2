import { describe, expect, it } from "vitest";

import {
  ACTIVITY_IDS,
  contentChecksum,
  validateActivityDraft,
  validateContentManifest,
  validatePublishedActivity,
} from "../../src/index.js";
import { makeAllPublishedPackages, makePublished, makeValidDraft, makeValidManifest } from "./package_fixture.js";

function issueCodes(value: { issues: { code: string }[] }): string[] {
  return value.issues.map((issue) => issue.code);
}

describe("activity semantic validation", () => {
  it("returns a field-addressable empty report for a valid authored draft", () => {
    expect(validateActivityDraft(makeValidDraft())).toEqual({ valid: true, issues: [], samples: [] });
  });

  it("rejects an unknown generator without silently substituting one", () => {
    const draft = structuredClone(makeValidDraft()) as unknown as Record<string, unknown>;
    const bands = draft.difficulty_bands as Record<string, unknown>[];
    bands[1]!.generator_id = "unknown_generator";

    const report = validateActivityDraft(draft);

    expect(report.valid).toBe(false);
    expect(report.issues).toContainEqual(
      expect.objectContaining({ path: ["difficulty_bands", 1, "generator_id"] }),
    );
  });

  it.each(["../escape.svg", "javascript:alert(1)", "https://evil.invalid/icon.svg"]) (
    "rejects arbitrary resource paths and URLs: %s",
    (badValue) => {
      const draft = { ...makeValidDraft(), icon_id: badValue };
      const report = validateActivityDraft(draft);

      expect(report.valid).toBe(false);
      expect(report.issues).toContainEqual(expect.objectContaining({ path: ["icon_id"] }));
    },
  );

  it("rejects cross-activity generators and unsafe tuning strings with exact paths", () => {
    const draft = structuredClone(makeValidDraft());
    draft.difficulty_bands[0]!.generator_id = "subtraction_v1";
    draft.difficulty_bands[2]!.generator_parameters.carry = "../remote-rules.json";

    const report = validateActivityDraft(draft);

    expect(issueCodes(report)).toContain("GENERATOR_ACTIVITY_MISMATCH");
    expect(issueCodes(report)).toContain("UNSAFE_TUNING_STRING");
    expect(report.issues).toContainEqual(
      expect.objectContaining({ path: ["difficulty_bands", 2, "generator_parameters", "carry"] }),
    );
  });

  it("rejects unordered combo thresholds, invalid adaptive bounds, and incomplete sample seeds", () => {
    const draft = structuredClone(makeValidDraft());
    draft.run.combo_thresholds = [4, 4, 2];
    draft.adaptive_policy = {
      enabled_by_default: false,
      min_band_id: "challenge",
      max_band_id: "intro",
      window_size: 5,
      promote_correctness: 0.3,
      demote_correctness: 0.7,
    };
    draft.validation_samples.pop();

    const report = validateActivityDraft(draft);

    expect(issueCodes(report)).toEqual(
      expect.arrayContaining(["COMBO_THRESHOLDS", "ADAPTIVE_BOUNDS", "ADAPTIVE_THRESHOLDS", "VALIDATION_SAMPLES"]),
    );
  });
});

describe("published package validation", () => {
  it("accepts only the checksum of the complete draft without the top-level checksum", () => {
    const published = makePublished();

    expect(validatePublishedActivity(published).valid).toBe(true);
    expect(
      issueCodes(validatePublishedActivity({ ...published, checksum: `sha256:${"0".repeat(64)}` })),
    ).toContain("CHECKSUM_MISMATCH");

    const changed = structuredClone(published);
    changed.run.goal.target += 1;
    expect(changed.checksum).not.toBe(contentChecksum(changed));
    expect(issueCodes(validatePublishedActivity(changed))).toContain("CHECKSUM_MISMATCH");
  });
});

describe("content manifest validation", () => {
  it("accepts the complete allowlisted catalogue from an array or path map", () => {
    const packages = makeAllPublishedPackages();
    const manifest = makeValidManifest(packages);
    const byPath = Object.fromEntries(manifest.packages.map((entry, index) => [entry.path, packages[index]]));

    expect(validateContentManifest(manifest, packages)).toEqual({ valid: true, issues: [], samples: [] });
    expect(validateContentManifest(manifest, byPath)).toEqual({ valid: true, issues: [], samples: [] });
  });

  it("rejects missing, duplicated, or reordered catalogue identities", () => {
    const packages = makeAllPublishedPackages();
    const manifest = makeValidManifest(packages);
    const duplicate = structuredClone(manifest);
    duplicate.packages[1] = structuredClone(duplicate.packages[0]!);
    const reordered = structuredClone(manifest);
    [reordered.activity_order[0], reordered.activity_order[1]] = [
      reordered.activity_order[1]!,
      reordered.activity_order[0]!,
    ];

    expect(validateContentManifest(manifest, packages.slice(1)).valid).toBe(false);
    expect(issueCodes(validateContentManifest(duplicate, packages))).toContain("MANIFEST_ACTIVITY_SET");
    expect(issueCodes(validateContentManifest(reordered, packages))).toContain("MANIFEST_ACTIVITY_ORDER");
  });

  it("rejects traversal, identity/path mismatch, and package checksum mismatch", () => {
    const packages = makeAllPublishedPackages();
    const manifest = makeValidManifest(packages);
    const traversal = structuredClone(manifest) as unknown as Record<string, unknown>;
    const entries = traversal.packages as Record<string, unknown>[];
    entries[0]!.path = "content/packages/../escape.json";
    const wrongPath = structuredClone(manifest);
    wrongPath.packages[0]!.path = `content/packages/${ACTIVITY_IDS[1]}/1.0.0.json`;
    const changedPackages = structuredClone(packages);
    changedPackages[0]!.run.goal.target += 1;

    expect(validateContentManifest(traversal, packages).valid).toBe(false);
    expect(issueCodes(validateContentManifest(wrongPath, packages))).toContain("MANIFEST_PACKAGE_PATH");
    expect(issueCodes(validateContentManifest(manifest, changedPackages))).toContain("CHECKSUM_MISMATCH");
  });
});
