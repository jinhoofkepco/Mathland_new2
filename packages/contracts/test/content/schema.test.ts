import { readFile } from "node:fs/promises";

import { describe, expect, it } from "vitest";

import {
  ActivityPackageDraftV1Schema,
  ActivityPackageV1Schema,
  ContentManifestV1Schema,
  generateContentJsonSchemas,
  renderJsonSchema,
} from "../../src/index.js";
import { makeAllPublishedPackages, makePublished, makeValidDraft, makeValidManifest } from "./package_fixture.js";

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
});
