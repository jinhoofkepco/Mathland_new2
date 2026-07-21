import { readFile } from "node:fs/promises";

import { describe, expect, it } from "vitest";

import {
  ACTIVITY_GENERATOR_IDS,
  ACTIVITY_IDS,
  ANSWER_LAYOUT_IDS,
  DIALOGUE_IDS,
  EFFECT_PRESET_IDS,
  GENERATOR_IDS,
  ICON_IDS,
  MANIPULATIVE_IDS,
  SCENE_IDS,
  parseJsonStrict,
  validateContentManifest,
} from "../../src/index.js";
import { renderGodotContentContract } from "../../../../tools/content/export_godot_contract.js";

const GENERATED_CONTRACT = new URL(
  "../../../../src/content/generated/content_contract_v1.gd",
  import.meta.url,
);
const GODOT_FIXTURE_ROOT = new URL("../../../../tests/content/fixtures/", import.meta.url);

describe("Godot content contract exporter", () => {
  it("renders deterministically and keeps the checked-in contract byte-for-byte current", async () => {
    const first = renderGodotContentContract();
    const second = renderGodotContentContract();
    const checkedIn = await readFile(GENERATED_CONTRACT, "utf8");

    expect(first).toBe(second);
    expect(checkedIn).toBe(first);
  });

  it("exports every canonical allowlist and activity-generator mapping", () => {
    const generated = renderGodotContentContract();
    const values = [
      ...ACTIVITY_IDS,
      ...GENERATOR_IDS,
      ...MANIPULATIVE_IDS,
      ...ANSWER_LAYOUT_IDS,
      ...SCENE_IDS,
      ...EFFECT_PRESET_IDS,
      ...ICON_IDS,
      ...DIALOGUE_IDS,
      ...Object.entries(ACTIVITY_GENERATOR_IDS).flat(),
    ];

    for (const value of values) {
      expect(generated).toContain(JSON.stringify(value));
    }
    expect(generated).toContain("const SCHEMA_VERSION := 1");
    expect(generated).toContain("const SAFE_INTEGER_MAX := 9007199254740991");
    expect(generated).toContain("const MAX_JSON_SOURCE_BYTES := 6000000");
    expect(generated).toContain("const MAX_JSON_NESTING := 64");
    expect(generated).toContain('const CHECKSUM_PREFIX := "sha256:"');
    expect(generated).toContain("const ACTIVITY_IDS := [");
    expect(generated).toContain("const VALIDATION_SEEDS := [1, 7, 42, 20260721]");
    expect(generated).not.toContain("static var ACTIVITY_IDS");
    expect(generated).not.toContain("static var VALIDATION_SEEDS");
  });

  it("keeps the Godot repository fixtures valid under the canonical TypeScript boundary", async () => {
    const manifest = parseJsonStrict(
      await readFile(new URL("minimal_manifest.json", GODOT_FIXTURE_ROOT), "utf8"),
    );
    expect(manifest).toEqual(expect.objectContaining({ packages: expect.any(Array) }));

    const entries = (manifest as { packages: { path: string }[] }).packages;
    const packagesByPath: Record<string, unknown> = {};
    for (const entry of entries) {
      packagesByPath[entry.path] = parseJsonStrict(
        await readFile(new URL(entry.path, GODOT_FIXTURE_ROOT), "utf8"),
      );
    }

    expect(validateContentManifest(manifest, packagesByPath)).toEqual({
      valid: true,
      issues: [],
      samples: [],
    });
    expect(
      parseJsonStrict(
        await readFile(new URL("minimal_valid_activity.json", GODOT_FIXTURE_ROOT), "utf8"),
      ),
    ).toEqual(packagesByPath["content/packages/addition_ones/1.0.0.json"]);
  });
});
