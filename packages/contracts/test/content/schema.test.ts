import { readFile } from "node:fs/promises";

import { Ajv2020, type ValidateFunction } from "ajv/dist/2020.js";
import { describe, expect, it } from "vitest";

import {
  ActivityPackageDraftV1Schema,
  ActivityPackageV1Schema,
  ContentManifestV1Schema,
  generateContentJsonSchemas,
  renderJsonSchema,
  type ActivityPackageV1,
} from "../../src/index.js";
import { makeAllPublishedPackages, makePublished, makeValidDraft, makeValidManifest } from "./package_fixture.js";

async function compileCheckedInActivitySchema(): Promise<ValidateFunction> {
  const schemaUrl = new URL(
    "../../src/content/activity-package-v1.schema.json",
    import.meta.url,
  );
  const schema = JSON.parse(await readFile(schemaUrl, "utf8")) as object;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  ajv.addKeyword({
    keyword: "x-mathland-semantic-validation",
    schemaType: "array",
    valid: true,
  });
  return ajv.compile(schema);
}

function validationErrors(validate: ValidateFunction): string {
  return JSON.stringify(validate.errors, null, 2);
}

describe("content package schemas", () => {
  it("accepts the strict draft and published package shapes", () => {
    const draft = makeValidDraft();
    const published = makePublished(draft);

    expect(ActivityPackageDraftV1Schema.parse(draft)).toEqual(draft);
    expect(ActivityPackageV1Schema.parse(published)).toEqual(published);
  });

  it("rejects unknown fields at every authored object boundary", () => {
    const draft = makeValidDraft() as unknown as Record<string, unknown>;
    const run = draft.run as Record<string, unknown>;
    run.remote_script = "javascript:alert(1)";

    const result = ActivityPackageDraftV1Schema.safeParse(draft);

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues).toContainEqual(
        expect.objectContaining({ code: "unrecognized_keys", path: ["run"] }),
      );
    }
  });

  it("requires lowercase semantic versions, exact checksums, and ISO timestamps", () => {
    const published = makePublished();
    const packages = makeAllPublishedPackages();
    const manifest = makeValidManifest(packages);

    expect(
      ActivityPackageV1Schema.safeParse({ ...published, content_version: "01.0.0" }).success,
    ).toBe(false);
    expect(
      ActivityPackageV1Schema.safeParse({ ...published, checksum: `sha256:${"A".repeat(64)}` }).success,
    ).toBe(false);
    expect(
      ContentManifestV1Schema.safeParse({ ...manifest, published_at: "next Tuesday" }).success,
    ).toBe(false);
  });

  it("structurally requires the ordered three-band shape and all eleven manifest entries", () => {
    const draft = makeValidDraft();
    const packages = makeAllPublishedPackages();
    const manifest = makeValidManifest(packages);

    expect(
      ActivityPackageDraftV1Schema.safeParse({
        ...draft,
        difficulty_bands: [draft.difficulty_bands[1], draft.difficulty_bands[0], draft.difficulty_bands[2]],
      }).success,
    ).toBe(false);
    expect(
      ContentManifestV1Schema.safeParse({ ...manifest, packages: manifest.packages.slice(1) }).success,
    ).toBe(false);
  });
});

describe("checked-in JSON Schemas", () => {
  it("stay byte-for-byte aligned with the Zod schema generator", async () => {
    const generated = generateContentJsonSchemas();
    const schemaDirectory = new URL("../../src/content/", import.meta.url);

    for (const [fileName, schema] of Object.entries(generated)) {
      const checkedIn = await readFile(new URL(fileName, schemaDirectory), "utf8");
      expect(JSON.parse(checkedIn)).toEqual(schema);
      expect(checkedIn).toBe(renderJsonSchema(schema));
    }
  });

  it.each([
    [
      "short combo_thresholds",
      (value: ActivityPackageV1) => ({
        ...value,
        run: { ...value.run, combo_thresholds: value.run.combo_thresholds.slice(0, 2) },
      }),
    ],
    [
      "long combo_thresholds",
      (value: ActivityPackageV1) => ({
        ...value,
        run: { ...value.run, combo_thresholds: [...value.run.combo_thresholds, 9] },
      }),
    ],
    [
      "short difficulty_bands",
      (value: ActivityPackageV1) => ({
        ...value,
        difficulty_bands: value.difficulty_bands.slice(0, 2),
      }),
    ],
    [
      "long difficulty_bands",
      (value: ActivityPackageV1) => ({
        ...value,
        difficulty_bands: [...value.difficulty_bands, value.difficulty_bands[2]],
      }),
    ],
  ])("reject %s through a Draft 2020-12 validator", async (_label, makeInvalid) => {
    const validate = await compileCheckedInActivitySchema();

    const validPackage = makePublished();
    expect(validate(validPackage), validationErrors(validate)).toBe(true);
    expect(validate(makeInvalid(validPackage)), validationErrors(validate)).toBe(false);
  });

  it.each([
    ["title leading whitespace", "title", " 덧셈"],
    ["title trailing whitespace", "title", "덧셈 "],
    ["title whitespace only", "title", "   "],
    ["description leading whitespace", "description", " 설명"],
    ["description trailing whitespace", "description", "설명 "],
    ["description whitespace only", "description", "\t"],
    ["tutorial leading whitespace", "tutorial_steps", " 단계"],
    ["tutorial trailing whitespace", "tutorial_steps", "단계 "],
    ["tutorial whitespace only", "tutorial_steps", "\n"],
  ] as const)("rejects %s through a Draft 2020-12 validator", async (_label, field, badText) => {
    const validate = await compileCheckedInActivitySchema();
    const validPackage = makePublished();
    const localization = validPackage.localizations["ko-KR"];
    const invalidLocalization =
      field === "tutorial_steps"
        ? { ...localization, tutorial_steps: [badText] }
        : { ...localization, [field]: badText };
    const invalidPackage = {
      ...validPackage,
      localizations: { "ko-KR": invalidLocalization },
    };

    expect(validate(validPackage), validationErrors(validate)).toBe(true);
    expect(validate(invalidPackage), validationErrors(validate)).toBe(false);
  });

  it.each([
    [40, true],
    [41, true],
    [80, true],
    [81, false],
  ] as const)(
    "keeps Zod and Draft 2020-12 maxLength parity for %i astral characters",
    async (characterCount, expectedValid) => {
      const validate = await compileCheckedInActivitySchema();
      const packageWithAstralTitle = makePublished();
      packageWithAstralTitle.localizations["ko-KR"].title = "😀".repeat(characterCount);

      const zodValid = ActivityPackageV1Schema.safeParse(packageWithAstralTitle).success;
      const jsonSchemaValid = validate(packageWithAstralTitle) as boolean;

      expect(zodValid).toBe(expectedValid);
      expect(jsonSchemaValid, validationErrors(validate)).toBe(expectedValid);
      expect(zodValid).toBe(jsonSchemaValid);
    },
  );
});
