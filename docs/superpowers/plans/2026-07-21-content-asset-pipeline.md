# Content and Asset Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver deterministic, validated, versioned content packages for five migrated MathLand activities and six foundations activities, together with safe expression/generator runtimes, reusable manipulatives, and redistribution-ready visual/audio assets.

**Architecture:** TypeScript contracts in `@mathland/contracts` are the canonical wire, schema, checksum, and editor-validation boundary; development tools under `tools/content/` convert, validate, sample, and bundle immutable packages. Equivalent Godot adapters under `src/content/` consume the bundled JSON through A's `ContentRepository` and `QuestionEngine` interfaces, with fixed cross-language fixtures proving parity. Project-native SVG/Godot assets cover UI and manipulatives, while reviewed raster masters and licensed offline audio are admitted only through manifests that record provenance and redistribution rights.

**Tech Stack:** Godot 4.7.1, typed GDScript, repository-owned headless Godot tests, TypeScript 5, npm workspaces, Zod 4, Vitest, Node.js SHA-256/canonical JSON tooling, SVG, PNG/WebP, Ogg Vorbis, FFmpeg/ffprobe, and the built-in `image_gen` workflow for approved raster candidates.

## Global Constraints

- Treat `docs/superpowers/specs/2026-07-21-mathland-godot-redesign-design.md` as the source of truth.
- Target Godot 4.7.1 with GDScript and the Compatibility renderer; do not add a Godot test plugin.
- Use `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content` and the corresponding `manipulatives` suite.
- Keep shared TypeScript content/event contracts in `packages/contracts/src/`; C imports them only as `@mathland/contracts`.
- Keep authored/versioned content under `content/`, conversion and validation entry points under `tools/content/`, and Godot runtime adapters/copies under `src/content/`.
- Preserve A's exact interfaces: `ContentRepository.get_activity(activity_id: StringName, content_version := "") -> Dictionary`, `ContentRepository.list_activities() -> Array[Dictionary]`, `ContentRepository.get_active_version(activity_id: StringName) -> String`, `ContentRepository.get_manifest_version() -> String`, and `QuestionEngine.generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary`.
- Manipulatives live in `src/game/manipulatives/` and preserve A's base API: `configure(config: Dictionary, question: Dictionary)`, `reset_state()`, `set_interaction_enabled(enabled: bool)`, `get_answer_state() -> Dictionary`, `apply_answer_state(state: Dictionary)`, and `answer_submitted(answer: Variant)`.
- All gameplay tuning, Korean instructional copy, answer layouts, effect preset IDs, and resource references are data; scenes contain no activity-specific learning rules or copy.
- Runtime accepts only schema version `1`, semantic content versions, allowlisted IDs/resource paths, and a checksum beginning `sha256:` followed by exactly 64 lowercase hexadecimal characters.
- Canonical checksums cover UTF-8 canonical JSON for every package field except the top-level `checksum`; object keys sort lexicographically, arrays retain order, and numbers use their JSON integer spelling.
- A run pins one immutable activity/content version. Content changes never alter a running question stream.
- Adaptive difficulty is absent or `enabled_by_default: false`; movement stays inside the package's declared minimum/maximum bands and does not change rules, rewards, or content version.
- Expression evaluation never invokes GDScript, JavaScript, shell syntax, network code, reflection, or an unregistered function.
- Every generated question records activity/content version, generator ID, band, seed, and resolved parameters so it is reproducible.
- The five development-only legacy fixtures come from `jinhoofkepco/SeoaQuiz` commit `08b9e7589a335f0c5674cfac6743132f8c4870f2`; runtime never parses legacy CSV.
- Ship new cohesive assets only; legacy raster assets are not release inputs.
- Author UI, icons, manipulatives, and scalable math graphics as reviewed SVG/Godot-native assets. Use AI image generation only for raster concept/production candidates after prompt and provenance recording.
- Built-in `image_gen` is the default image path. Project-bound outputs must be copied from `$CODEX_HOME/generated_images/` into the workspace; distinct assets use distinct calls; no output remains referenced only from `$CODEX_HOME`.
- Simple transparent generated assets use a flat chroma-key source plus the installed `remove_chroma_key.py` helper. True/native transparency via CLI `gpt-image-1.5` requires explicit user approval and `OPENAI_API_KEY`; never switch silently.
- Generated art must pass human review for Moa consistency, mathematical marks, unwanted text, artifacts, child appropriateness, and alpha edges before entering the release manifest.
- Release audio is bundled for offline use. System voices are audition-only; every distributable voice/music/SFX file must have confirmed bundling and redistribution rights in `ASSET_LICENSES.md`.
- Voice uses stable dialogue IDs, never blocks input, and question narration is played only from a speaker control.
- Do not add real names, birth dates, child event logs, credentials, provider keys, personal contacts, development URLs, or proprietary signing material to content or assets.
- Run the named red test before implementation, retain its observed failure in task notes, and commit only after the task's full green command passes.

## File and Responsibility Map

| Path | Responsibility |
|---|---|
| `packages/contracts/src/content/` | Canonical TypeScript content types, Zod schemas, allowlists, canonical JSON/checksum logic, validation reports, deterministic reference generators |
| `packages/contracts/test/content/` | Contract, schema, checksum, expression, generator, and sample-validation tests shared with C |
| `content/sources/` | Human-edited package drafts without checksums |
| `content/packages/addition_ones/1.0.0.json` (same layout for every catalogue ID) | Generated immutable, checksummed runtime packages |
| `content/manifests/1.0.0.json` | Immutable manifest listing all 11 package paths and checksums |
| `content/active-manifest.json` | Bundled release publication pointer for offline first launch |
| `content/locales/ko-KR.json` | Centralized system/content labels not embedded in scenes |
| `tools/content/` | CLI wrappers, legacy converter, bundle builder, parity fixture exporter, and independent answer verifier |
| `src/content/` | Godot content validator, repository, expression engine, deterministic RNG, generator registry, and generator implementations |
| `src/game/manipulatives/` | A-compatible base class plus counters, ten frame, base-ten blocks, number line, and answer-slot scenes |
| `tests/content/` | Headless Godot content, expression, generator, repository, and legacy parity tests |
| `tests/manipulatives/` | SceneTree tests for manipulative configuration, state, interaction, and submitted answers |
| `assets/ui/` | Reviewed SVG icons and learning graphics |
| `assets/art/` | Final PNG raster exports referenced by the game |
| `assets/audio/` | Final offline music, SFX, and voice Ogg files |
| `assets/source/` | Versioned prompts, art/audio masters, review records, and non-release audition metadata |
| `tools/assets/` | Asset-manifest, raster/SVG, and audio technical validators |
| `ASSET_LICENSES.md` | Per-asset origin, author/tool, source, license, modification, and redistribution status |

---

### Task 1: Establish the Shared Content-Contract Workspace

**Files:**

- Modify: `package.json`
- Modify: `package-lock.json` through `npm install`
- Create: `packages/contracts/package.json`
- Create: `packages/contracts/tsconfig.json`
- Create: `packages/contracts/vitest.config.ts`
- Create: `packages/contracts/src/content/types.ts`
- Create: `packages/contracts/src/content/ids.ts`
- Create: `packages/contracts/src/events/learning_event_v1.ts`
- Create: `packages/contracts/src/index.ts`
- Test: `packages/contracts/test/content/types.test.ts`
- Test: `packages/contracts/test/events/learning_event_v1.test.ts`

**Interfaces:**

- Consumes: the repository root; merge with any existing npm scripts if another subproject has already added them.
- Produces: `ActivityPackageDraftV1`, `ActivityPackageV1`, `ContentManifestV1`, `QuestionInstanceV1`, `AnswerValueV1`, `ValidationIssue`, `ValidationReport`, `LearningEventV1`, `LearningEventV1Schema`, and exported ID allowlists from `@mathland/contracts`.

- [ ] **Step 1: Write the failing contract-shape test**

```ts
import { describe, expect, it } from "vitest";
import { ACTIVITY_IDS, GENERATOR_IDS, MANIPULATIVE_IDS } from "../../src/index.js";

describe("content contract IDs", () => {
  it("publishes the complete 1.0 activity catalogue", () => {
    expect(ACTIVITY_IDS).toEqual([
      "addition_ones", "subtraction_ones", "multiplication",
      "common_multiples_lcm", "prime_factorization",
      "foundations_counting", "foundations_number_bonds",
      "foundations_ten_frame", "foundations_base_ten",
      "foundations_number_line", "foundations_basic_operations",
    ]);
    expect(GENERATOR_IDS).toHaveLength(11);
    expect(MANIPULATIVE_IDS).toEqual([
      "none", "counters", "ten_frame", "base_ten", "number_line", "answer_slots",
    ]);
  });
});
```

Add `packages/contracts/test/events/learning_event_v1.test.ts`; it reads `tests/fixtures/contracts/learning_event_v1.json`, parses it through `LearningEventV1Schema`, compares the exact top-level key set and values, rejects an unknown key, rejects a non-UUID event ID and nonpositive sequence, and verifies `session_id` is optional only where the Godot contract permits it. This is the Gate 1 cross-language event parity test.

- [ ] **Step 2: Run the focused test and verify red**

Run: `npm run test:contracts -- --run test/content/types.test.ts test/events/learning_event_v1.test.ts`

Expected: FAIL because `@mathland/contracts`, its content exports, and `LearningEventV1Schema` do not exist.

- [ ] **Step 3: Add the workspace scripts and package metadata**

Create the root workspace when absent, or merge these scripts and workspace globs without removing existing entries:

```json
{
  "scripts": {
    "test:contracts": "npm --workspace @mathland/contracts test",
    "test:content-tools": "npm --workspace @mathland/contracts test -- --run test/content test/tools",
    "validate:content": "tsx tools/content/validate_content.ts --manifest content/active-manifest.json",
    "build:content": "tsx tools/content/build_content.ts"
  },
  "workspaces": ["packages/*", "web"]
}
```

Create `@mathland/contracts` as a private ESM workspace with TypeScript, Vitest, Zod 4, `@noble/hashes`, and `tsx`. Export `./content` and the root barrel. Do not overwrite scripts/workspaces added by A, C, or D.

- [ ] **Step 4: Define the exact public types and allowlists**

```ts
export type AnswerValueV1 =
  | { kind: "integer"; value: number }
  | { kind: "integer_list"; values: number[]; order_matters: boolean };

export interface QuestionInstanceV1 {
  contract_version: 1;
  activity_id: ActivityId;
  content_version: string;
  generator_id: GeneratorId;
  band_id: string;
  seed: number;
  resolved_parameters: Record<string, boolean | number | string | number[]>;
  prompt: { key: string; args: Record<string, number | string> };
  correct_answer: AnswerValueV1;
  answer_layout: AnswerLayoutV1;
  manipulative: ManipulativeConfigV1;
}

export interface ValidationReport {
  valid: boolean;
  issues: ValidationIssue[];
  samples: QuestionInstanceV1[];
}
```

`ids.ts` exports readonly arrays for the 11 activity IDs, matching generator IDs (`addition_v1` through `basic_operations_v1`), the six manipulative IDs, answer layouts (`numeric_keypad`, `choice_grid`, `factor_slots`, `manipulative_submit`), scene ID `activity_run`, named effect presets from A, and all final icon/dialogue IDs.

Define `LearningEventV1` with the exact Godot fixture names: `contract_version`, `event_id`, `profile_id`, `device_id`, optional `session_id`, positive integer `sequence`, ISO client timestamp, event type, and the reproducibility/answer/health/combo/reward fields from the approved contract. Use a strict discriminated Zod union for `run_started`, `answer_submitted`, `run_completed`, `collection_unlocked`, and `coupon_earned`; `answer_submitted` requires activity/content/generator/band/seed/resolved parameters, submitted/correct answer, correctness, nonnegative response duration/hints, health delta, combo, and reward delta. Reject unknown keys and unsafe integers.

- [ ] **Step 5: Run contract tests and type checking**

Run: `npm run test:contracts -- --run test/content/types.test.ts test/events/learning_event_v1.test.ts && npm --workspace @mathland/contracts run typecheck`

Expected: the catalogue/type tests and Godot-fixture event parity tests pass and TypeScript reports zero errors.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json packages/contracts
git commit -m "build(contracts): establish shared content contract"
```

### Task 2: Define Schema, Canonical JSON, Checksums, and Semantic Validation

**Files:**

- Create: `packages/contracts/src/content/schema.ts`
- Create: `packages/contracts/src/content/canonical_json.ts`
- Create: `packages/contracts/src/content/checksum.ts`
- Create: `packages/contracts/src/content/validate.ts`
- Create: `packages/contracts/src/content/json_schema.ts`
- Create: `packages/contracts/src/content/activity-package-v1.schema.json`
- Create: `packages/contracts/src/content/content-manifest-v1.schema.json`
- Modify: `packages/contracts/src/index.ts`
- Test: `packages/contracts/test/content/schema.test.ts`
- Test: `packages/contracts/test/content/checksum.test.ts`
- Test: `packages/contracts/test/content/validate.test.ts`

**Interfaces:**

- Consumes: Task 1 types and allowlists.
- Produces: `ActivityPackageDraftV1Schema`, `ActivityPackageV1Schema`, `ContentManifestV1Schema`, `canonicalJson(value)`, `contentChecksum(draft)`, `validateActivityDraft(value)`, `validatePublishedActivity(value)`, and `validateContentManifest(value, packages)`.

- [ ] **Step 1: Write red tests for checksum and rejection cases**

```ts
it("canonicalizes recursively and excludes only the package checksum", async () => {
  const a = { schema_version: 1, content_version: "1.0.0", activity_id: "addition_ones", z: [2, 1], a: { y: 2, x: 1 }, checksum: "ignored" };
  const b = { a: { x: 1, y: 2 }, activity_id: "addition_ones", content_version: "1.0.0", schema_version: 1, z: [2, 1] };
  expect(canonicalJson(a, { omitTopLevel: ["checksum"] })).toBe(canonicalJson(b));
  expect(await contentChecksum(a)).toMatch(/^sha256:[0-9a-f]{64}$/);
  expect(await contentChecksum(a)).toBe(await contentChecksum(b));
});

it.each(["unknown_generator", "../escape.svg", "javascript:alert(1)"])(
  "rejects unregistered identifiers or paths: %s",
  async (badValue) => expect((await validateActivityDraft(makeDraftWith(badValue))).valid).toBe(false),
);
```

- [ ] **Step 2: Run tests and verify red**

Run: `npm run test:contracts -- --run test/content/schema.test.ts test/content/checksum.test.ts test/content/validate.test.ts`

Expected: FAIL with unresolved schema/checksum/validator exports.

- [ ] **Step 3: Implement the complete package schema**

The Zod schema and checked-in JSON Schema must require this shape:

```ts
export interface ActivityPackageDraftV1 {
  schema_version: 1;
  content_version: `${number}.${number}.${number}`;
  activity_id: ActivityId;
  localizations: Record<"ko-KR", {
    title: string;
    description: string;
    tutorial_steps: string[];
  }>;
  icon_id: IconId;
  scene_id: "activity_run";
  run: {
    starting_hearts: number;
    goal: { kind: "correct_answers"; target: number };
    timer: { enabled: boolean; seconds: number; profile_can_disable: boolean };
    rewards: { apples_per_correct: number; completion_apples: number };
    combo_thresholds: [number, number, number];
    boss_every_correct: number;
    effects: { correct: string; wrong: string; combo: string; boss: string; level_up: string; reward: string; health_loss: string };
  };
  difficulty_bands: DifficultyBandV1[];
  adaptive_policy?: { enabled_by_default: false; min_band_id: string; max_band_id: string; window_size: number; promote_correctness: number; demote_correctness: number };
  validation_samples: { band_id: string; seed: number; expected_answer: AnswerValueV1 }[];
}

export interface ActivityPackageV1 extends ActivityPackageDraftV1 {
  checksum: `sha256:${string}`;
}
```

Enforce nonempty trimmed Korean copy, exactly three ordered unique bands (`intro`, `practice`, `challenge`), three starting hearts unless explicitly authored otherwise, positive goals/timers/rewards, strictly increasing combo thresholds, adaptive bounds referring to existing bands, four validation seeds per band (`1`, `7`, `42`, `20260721`), known IDs only, and resource IDs rather than arbitrary paths.

- [ ] **Step 4: Implement canonical checksum and manifest validation**

`canonicalJson` rejects `undefined`, functions, symbols, non-finite numbers, duplicate object keys after parsing, and unsafe integers. `contentChecksum` hashes UTF-8 canonical JSON after removing only the top-level checksum. `ContentManifestV1` requires schema `1`, manifest version `1.0.0`, ISO timestamp, 11 unique activity entries, package paths matching `content/packages/` + the exact allowlisted activity ID + `/` + the exact semantic content version + `.json`, and checksum equality with each parsed package.

- [ ] **Step 5: Generate and drift-check JSON Schemas**

`json_schema.ts` writes both schemas in stable two-space JSON. Add a test that generates in memory and deep-compares the checked-in files, so TypeScript and Content Studio cannot drift.

- [ ] **Step 6: Run the complete contract suite**

Run: `npm run test:contracts && npm --workspace @mathland/contracts run typecheck`

Expected: schema, traversal, allowlist, checksum, manifest, and type tests all pass with zero TypeScript errors.

- [ ] **Step 7: Commit**

```bash
git add packages/contracts/src/content packages/contracts/test/content
git commit -m "feat(content): define versioned package validation"
```

### Task 3: Implement the Godot Content Contract and Repository

**Files:**

- Create: `tools/content/export_godot_contract.ts`
- Create: `src/content/generated/content_contract_v1.gd`
- Create: `src/content/content_validation_result.gd`
- Create: `src/content/content_validator.gd`
- Modify: `src/content/content_repository.gd`
- Create: `tests/content/fixtures/minimal_valid_activity.json`
- Create: `tests/content/fixtures/minimal_manifest.json`
- Create: `tests/content/content_contract_parity_test.gd`
- Create: `tests/content/content_repository_test.gd`
- Test: `packages/contracts/test/tools/export_godot_contract.test.ts`

**Interfaces:**

- Consumes: Task 2 schemas, canonicalization rules, and A's `ContentRepository` stub.
- Produces: A's exact `get_activity`, immutable-summary `list_activities`, per-activity `get_active_version`, and `get_manifest_version` behavior plus `initialize(bundled_manifest_path := "res://content/active-manifest.json", cache_root := "user://content") -> ContentValidationResult` and `validate_package(package: Dictionary) -> ContentValidationResult`.

- [ ] **Step 1: Write failing exporter and repository tests**

```gdscript
func test_returns_deep_copy_and_pins_requested_version() -> void:
    var repository := ContentRepository.new()
    assert_true(repository.initialize("res://tests/content/fixtures/minimal_manifest.json").ok)
    var first := repository.get_activity(&"addition_ones", "1.0.0")
    first["run"]["starting_hearts"] = 99
    var second := repository.get_activity(&"addition_ones", "1.0.0")
    assert_eq(second["run"]["starting_hearts"], 3)
    assert_eq(repository.get_active_version(&"addition_ones"), "1.0.0")
    assert_eq(repository.get_manifest_version(), "1.0.0")
```

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/tools/export_godot_contract.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: TypeScript fails on the missing exporter and Godot fails on missing validation/repository behavior.

- [ ] **Step 3: Generate the Godot contract constants**

`export_godot_contract.ts` imports the Task 1 allowlists and emits deterministic `PackedStringArray` constants, schema version, safe integer bounds, required package keys, and checksum prefix. The test compares the full generated string with `src/content/generated/content_contract_v1.gd`; manual edits to the generated file fail.

- [ ] **Step 4: Implement runtime validation and repository fallback**

```gdscript
func get_activity(activity_id: StringName, content_version := "") -> Dictionary:
    var version: String = content_version if not content_version.is_empty() else _active_versions.get(String(activity_id), "")
    var key := "%s@%s" % [activity_id, version]
    if not _packages.has(key):
        return {}
    return _packages[key].duplicate(true)

func list_activities() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for activity_id in _manifest.get("activity_order", []):
        var package := get_activity(StringName(activity_id))
        result.append({"activity_id": activity_id, "title": package.title, "icon_id": package.icon_id}.duplicate(true))
    return result

func get_active_version(activity_id: StringName) -> String:
    return _active_versions.get(String(activity_id), "")

func get_manifest_version() -> String:
    return _manifest.get("manifest_version", "")
```

Initialization validates the cached manifest/package set first, then the bundled set. A bad checksum, unknown ID, invalid JSON, missing file, unsupported schema, or path traversal rejects the entire candidate set and never replaces a previously valid in-memory set. JSON objects are deep-copied on return so scenes cannot mutate repository state.

- [ ] **Step 5: Run TypeScript and Godot tests**

Run: `npm run test:contracts -- --run test/tools/export_godot_contract.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: exporter parity, cache rejection, bundled fallback, version pinning, checksum rejection, and immutable-copy tests pass.

- [ ] **Step 6: Commit**

```bash
git add tools/content/export_godot_contract.ts src/content tests/content packages/contracts/test/tools
git commit -m "feat(godot): validate and load immutable content"
```

### Task 4: Build the Safe Cross-Language Expression Engine

**Files:**

- Create: `packages/contracts/src/content/expression/tokens.ts`
- Create: `packages/contracts/src/content/expression/parser.ts`
- Create: `packages/contracts/src/content/expression/evaluate.ts`
- Create: `src/content/expression/expression_result.gd`
- Create: `src/content/expression/expression_engine.gd`
- Create: `tests/content/fixtures/expression_cases.json`
- Test: `packages/contracts/test/content/expression.test.ts`
- Test: `tests/content/expression_engine_test.gd`

**Interfaces:**

- Consumes: Task 1 safe integer bounds.
- Produces: TypeScript `evaluateExpression(source, variables) -> ExpressionResult` and GDScript `ExpressionEngine.evaluate(source: String, variables := {}) -> ExpressionResult`, with identical result/error codes.

- [ ] **Step 1: Create shared grammar fixtures and failing tests**

`expression_cases.json` must include `2+3*4 = 14`, `(2+3)*4 = 20`, `A*10+B` with variables, `mod(17,5) = 2`, `quotient(17,5) = 3`, `digit(12345,3) = 3`, `gcd(18,24) = 6`, `lcm(6,8) = 24`, unary minus, whitespace, division by zero, non-integral division, unknown identifiers/functions, malformed commas/brackets, excessive depth, excessive tokens, unsafe integer overflow, and trailing input.

- [ ] **Step 2: Verify both implementations are red**

Run: `npm run test:contracts -- --run test/content/expression.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL because the expression modules do not exist.

- [ ] **Step 3: Implement the explicit grammar**

```text
expression  := additive
additive    := multiplicative (("+" | "-") multiplicative)*
multiplicative := unary (("*" | "/" | "%") unary)*
unary       := "-" unary | primary
primary     := INTEGER | IDENTIFIER | "(" expression ")" | FUNCTION "(" arguments ")"
FUNCTION    := "mod" | "quotient" | "digit" | "gcd" | "lcm"
arguments   := expression "," expression
```

Both implementations use signed safe integers, maximum source length 512, maximum 128 tokens, maximum nesting 16, exact integral `/`, quotient truncating toward zero, positive modulo divisor, one-based digit positions from the right, and stable codes `EMPTY`, `INVALID_TOKEN`, `UNKNOWN_IDENTIFIER`, `UNKNOWN_FUNCTION`, `ARITY`, `DIVIDE_BY_ZERO`, `NON_INTEGRAL_DIVISION`, `DIGIT_RANGE`, `OVERFLOW`, `TOO_COMPLEX`, and `TRAILING_INPUT`.

- [ ] **Step 4: Keep evaluators independent of platform execution APIs**

Use recursive-descent parsing over token arrays. Do not use `eval`, `Expression`, `GDScript`, `Callable` lookup by untrusted name, regex replacement evaluation, or dynamic loading. Dispatch the five functions through a literal switch/match.

- [ ] **Step 5: Run parity suites**

Run: `npm run test:contracts -- --run test/content/expression.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: all valid fixtures return the same integers and all invalid fixtures return the same error code/offset in TypeScript and Godot.

- [ ] **Step 6: Commit**

```bash
git add packages/contracts/src/content/expression packages/contracts/test/content/expression.test.ts src/content/expression tests/content
git commit -m "feat(content): add safe expression grammar"
```

### Task 5: Add Deterministic RNG, Generator Contracts, and QuestionEngine

**Files:**

- Create: `packages/contracts/src/content/generation/rng.ts`
- Create: `packages/contracts/src/content/generation/types.ts`
- Create: `packages/contracts/src/content/generation/registry.ts`
- Create: `packages/contracts/src/content/generation/adaptive_band.ts`
- Create: `src/content/generation/seeded_rng.gd`
- Create: `src/content/generation/question_generator.gd`
- Create: `src/content/generation/generator_registry.gd`
- Create: `src/content/adaptive_band_selector.gd`
- Modify: `src/content/question_engine.gd`
- Create: `tests/content/fixtures/rng_vectors.json`
- Test: `packages/contracts/test/content/rng.test.ts`
- Test: `packages/contracts/test/content/adaptive_band.test.ts`
- Test: `tests/content/question_engine_test.gd`
- Test: `tests/content/adaptive_band_selector_test.gd`

**Interfaces:**

- Consumes: A's exact `QuestionEngine.generate_question` stub, profile `adaptive_difficulty` setting, recent immutable answer events, and Task 1 `QuestionInstanceV1`.
- Produces: xorshift32 RNG parity, typed generator registry, deterministic question envelope creation, and `AdaptiveBandSelector.select(activity, fixed_band_id, recent_events, enabled) -> StringName`.

- [ ] **Step 1: Write red RNG and envelope tests**

The seed `0x12345678` must yield unsigned values `2274908837, 358294691, 1210119364, 2176035992, 1882851208`. Seed zero normalizes to `0x6d2b79f5`. Test `range_int` inclusive bounds, deterministic weighted picks, unknown generator/band rejection, and identical envelopes for repeated inputs. Test adaptive disabled always returns the published fixed band; adaptive enabled uses only the policy window, promotes/demotes at authored thresholds, and never crosses declared minimum/maximum bands. Empty or insufficient history keeps the current band, and selection never mutates run, reward, or content-version fields.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/rng.test.ts test/content/adaptive_band.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL on missing RNG/registry/QuestionEngine behavior.

- [ ] **Step 3: Implement the generator interface and registry**

```gdscript
class_name QuestionGenerator
extends RefCounted

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
    return PackedStringArray()

func generate(activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
    push_error("QuestionGenerator.generate must be overridden")
    return {}
```

The registry is a literal allowlist mapping the 11 IDs to constructors. `QuestionEngine` finds exactly one band, creates a fresh generator/RNG, validates parameters, and returns the Task 1 envelope with deep-copied resolved parameters. It returns `{}` plus a diagnostic for unknown IDs/bands or invalid generator output; it never silently substitutes another band.

`AdaptiveBandSelector` receives the pinned package and fixed/current band. When disabled or when the package has no adaptive policy it returns `fixed_band_id` without reading history. When enabled it examines at most `window_size` recent events for the same activity/content version, computes correctness plus authored hint/repeated-error penalties, moves at most one adjacent band, clamps to `min_band_id..max_band_id`, and returns only the selected band ID. `RunController` continues to own health, target, timer, rewards, and immutable content version.

- [ ] **Step 4: Export the same registry contract to TypeScript**

The TypeScript registry uses the same parameter validation and is the independent Content Studio/build-time reference. It must not import Godot code or read files/network/time.

- [ ] **Step 5: Run parity tests**

Run: `npm run test:contracts -- --run test/content/rng.test.ts test/content/adaptive_band.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: RNG vectors, range/pick behavior, fixed/adaptive band decisions, band lookup, and deterministic envelope tests pass in TypeScript and Godot.

- [ ] **Step 6: Commit**

```bash
git add packages/contracts/src/content/generation packages/contracts/test/content/rng.test.ts packages/contracts/test/content/adaptive_band.test.ts src/content/generation src/content/adaptive_band_selector.gd src/content/question_engine.gd tests/content
git commit -m "feat(content): add deterministic question engine"
```

### Task 6: Implement Addition, Subtraction, and Multiplication Generators

**Files:**

- Create: `packages/contracts/src/content/generation/arithmetic.ts`
- Create: `src/content/generation/generators/addition_generator.gd`
- Create: `src/content/generation/generators/subtraction_generator.gd`
- Create: `src/content/generation/generators/multiplication_generator.gd`
- Modify: `packages/contracts/src/content/generation/registry.ts`
- Modify: `src/content/generation/generator_registry.gd`
- Create: `tests/content/fixtures/arithmetic_generator_cases.json`
- Test: `packages/contracts/test/content/arithmetic_generators.test.ts`
- Test: `tests/content/arithmetic_generators_test.gd`

**Interfaces:**

- Consumes: `QuestionGenerator`, `SeededRng`, expression-safe integers.
- Produces: `addition_v1`, `subtraction_v1`, and `multiplication_v1` with identical TypeScript/Godot output.

- [ ] **Step 1: Write failing parameter and property tests**

Test exact seeds plus 1,000 seeds per parameter case. Addition parameters are `operand_count: 2|3`, `operand_min`, `operand_max`, `place_mode: "full"|"ones_digit"`, and `carry: "allow"|"forbid"|"require"`. Subtraction adds `allow_negative: false` and `borrow` with the same enum. Multiplication uses `left_min`, `left_max`, `right_min`, `right_max`, and `display: "horizontal"|"column"`. Independently recompute every answer and assert bounds/carry/borrow policies.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/arithmetic_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL because arithmetic generators are unregistered.

- [ ] **Step 3: Implement minimal deterministic generation**

Generate operands only through the supplied RNG. Rejection sampling is capped at 128 attempts and then returns `UNSATISFIABLE_PARAMETERS`; no generator relaxes authored constraints. Resolved parameters include operands, operator, carry/borrow status, display mode, and computed answer. Prompt keys are `question.addition`, `question.subtraction`, and `question.multiplication`; answers are integer answers.

- [ ] **Step 4: Run focused and property suites**

Run: `npm run test:contracts -- --run test/content/arithmetic_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: fixed-seed parity and 3,000 independently verified generated questions pass.

- [ ] **Step 5: Commit**

```bash
git add packages/contracts/src/content/generation src/content/generation packages/contracts/test/content/arithmetic_generators.test.ts tests/content
git commit -m "feat(content): add deterministic arithmetic generators"
```

### Task 7: Implement Common-Multiple/LCM and Prime-Factorization Generators

**Files:**

- Create: `packages/contracts/src/content/generation/number_theory.ts`
- Create: `src/content/generation/generators/common_multiple_generator.gd`
- Create: `src/content/generation/generators/prime_factorization_generator.gd`
- Modify: both generator registries
- Create: `tests/content/fixtures/number_theory_generator_cases.json`
- Test: `packages/contracts/test/content/number_theory_generators.test.ts`
- Test: `tests/content/number_theory_generators_test.gd`

**Interfaces:**

- Produces: `common_multiple_v1` integer-answer questions and `prime_factorization_v1` ordered integer-list answers.

- [ ] **Step 1: Write failing mathematical-property tests**

LCM parameters are `operand_count: 2|3`, `operand_min`, `operand_max`, and `require_distinct`; verify the answer is divisible by every operand and no smaller positive common multiple exists. Prime-factorization parameters are `value_min`, `value_max`, `factor_count_min`, `factor_count_max`, and `allowed_primes`; verify every listed factor is prime, the list is ascending, multiplicity is preserved, and the product equals the prompt value.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/number_theory_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL because both number-theory generators are missing.

- [ ] **Step 3: Implement bounded number-theory helpers and generators**

Use Euclid's algorithm for GCD, overflow-checked `abs(a / gcd * b)` for LCM, and trial division only over the authored prime allowlist. Cap candidate attempts at 128 and return a structured parameter error when no valid value exists. `prime_factorization_v1` uses `factor_slots`; LCM uses `numeric_keypad`.

- [ ] **Step 4: Run parity/property suites**

Run: `npm run test:contracts -- --run test/content/number_theory_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: fixed-seed parity and 2,000 independently verified number-theory questions pass.

- [ ] **Step 5: Commit**

```bash
git add packages/contracts/src/content/generation src/content/generation packages/contracts/test/content/number_theory_generators.test.ts tests/content
git commit -m "feat(content): add number theory generators"
```

### Task 8: Implement the Six Foundations Generators

**Files:**

- Create: `packages/contracts/src/content/generation/foundations.ts`
- Create: `src/content/generation/generators/counting_generator.gd`
- Create: `src/content/generation/generators/number_bond_generator.gd`
- Create: `src/content/generation/generators/ten_frame_generator.gd`
- Create: `src/content/generation/generators/base_ten_generator.gd`
- Create: `src/content/generation/generators/number_line_generator.gd`
- Create: `src/content/generation/generators/basic_operations_generator.gd`
- Modify: both generator registries
- Create: `tests/content/fixtures/foundations_generator_cases.json`
- Test: `packages/contracts/test/content/foundations_generators.test.ts`
- Test: `tests/content/foundations_generators_test.gd`

**Interfaces:**

- Produces: `counting_v1`, `number_bonds_v1`, `ten_frame_v1`, `base_ten_v1`, `number_line_v1`, and `basic_operations_v1` question/manipulative states.

- [ ] **Step 1: Write failing foundation invariants**

Test counting one-to-one item counts; number-bond parts summing to the whole; ten-frame occupied cells equal to target and use row-major fill; base-ten hundreds/tens/ones decompose and reconstruct the number; number-line start plus signed steps equals endpoint and stays in bounds; basic addition/subtraction uses nonnegative age-appropriate operands. Run 1,000 seeds for each generator and all three bands.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/foundations_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL with six missing generator registrations.

- [ ] **Step 3: Implement exact parameter contracts**

Counting uses `count_min/count_max`; bonds use `whole_min/whole_max/show_part`; ten frames use `target_min/target_max/frame_count`; base ten uses `value_min/value_max/max_place`; number line uses `axis_min/axis_max/step_min/step_max/direction`; basic operations uses `operators`, operand bounds, and `allow_negative: false`. Each output supplies the correct manipulative ID and a serializable initial state with only integers, booleans, strings, and arrays.

- [ ] **Step 4: Run deterministic/property tests**

Run: `npm run test:contracts -- --run test/content/foundations_generators.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: 18,000 foundation samples pass mathematical bounds and TypeScript/Godot fixed-seed parity.

- [ ] **Step 5: Commit**

```bash
git add packages/contracts/src/content/generation src/content/generation packages/contracts/test/content/foundations_generators.test.ts tests/content
git commit -m "feat(content): add foundations generators"
```

### Task 9: Build Reusable Manipulatives and the Data-Driven Activity Host

**Files:**

- Modify: `src/game/manipulatives/manipulative.gd`
- Create: `src/game/manipulatives/counters/counters.gd`
- Create: `src/game/manipulatives/counters/counters.tscn`
- Create: `src/game/manipulatives/ten_frame/ten_frame.gd`
- Create: `src/game/manipulatives/ten_frame/ten_frame.tscn`
- Create: `src/game/manipulatives/base_ten/base_ten.gd`
- Create: `src/game/manipulatives/base_ten/base_ten.tscn`
- Create: `src/game/manipulatives/number_line/number_line.gd`
- Create: `src/game/manipulatives/number_line/number_line.tscn`
- Create: `src/game/manipulatives/answer_slots/answer_slots.gd`
- Create: `src/game/manipulatives/answer_slots/answer_slots.tscn`
- Create: `src/game/manipulatives/manipulative_factory.gd`
- Create: `src/ui/game/answer_inputs/answer_input.gd`
- Create: `src/ui/game/answer_inputs/numeric_keypad.gd`
- Create: `src/ui/game/answer_inputs/numeric_keypad.tscn`
- Create: `src/ui/game/answer_inputs/choice_grid.gd`
- Create: `src/ui/game/answer_inputs/choice_grid.tscn`
- Create: `src/ui/game/answer_inputs/factor_slots.gd`
- Create: `src/ui/game/answer_inputs/factor_slots.tscn`
- Create: `src/ui/game/answer_input_factory.gd`
- Modify: `src/ui/game/activity_run.gd`
- Test: `tests/manipulatives/manipulative_contract_test.gd`
- Test: `tests/manipulatives/foundation_manipulatives_test.gd`
- Test: `tests/manipulatives/activity_host_test.gd`

**Interfaces:**

- Consumes: A's exact manipulative base API, A's generic `ActivityRun`, Task 8 serializable states, and package fields `answer_layout`/`manipulative`.
- Produces: Five allowlisted scenes created by `ManipulativeFactory.create(id: StringName) -> Manipulative`, answer controls created by `AnswerInputFactory.create(layout_id: StringName) -> AnswerInput`, and one package-driven host for all eleven activities.

- [ ] **Step 1: Write the failing shared contract test**

```gdscript
func test_every_manipulative_round_trips_state_and_submits() -> void:
    for id in [&"counters", &"ten_frame", &"base_ten", &"number_line", &"answer_slots"]:
        var node := ManipulativeFactory.create(id)
        add_child_autofree(node)
        node.configure(FIXTURE_CONFIGS[id], FIXTURE_QUESTIONS[id])
        var saved := node.get_answer_state().duplicate(true)
        node.reset_state()
        node.apply_answer_state(saved)
        assert_eq(node.get_answer_state(), saved)
        node.set_interaction_enabled(false)
        assert_false(node.is_interaction_enabled())
```

Add a host test that loads one fixed question fixture for every activity ID, instantiates the package-selected manipulative and answer layout, submits its known correct answer, and asserts `ActivityRun` forwards the canonical `AnswerValueV1` to `RunSession` without an activity-ID branch. Unknown layout/manipulative IDs must fail before a run starts.

- [ ] **Step 2: Run the manipulative suite and verify red**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite manipulatives`

Expected: FAIL because the manipulative/input factories and reusable scenes do not exist.

- [ ] **Step 3: Implement behavior without activity rules**

Counters expose ordered occupancy; ten frame exposes row-major boolean cells across one or two frames; base ten exposes counts for hundreds/tens/ones; number line exposes selected endpoint and visited ticks; answer slots expose integer tokens. All scenes use Containers/anchors, minimum 48dp-equivalent touch targets, shape/text cues in addition to color, immediate touch-down feedback through A's tactile button/effects ports, and no file/network/global-progress calls.

- [ ] **Step 4: Verify submission and reset semantics**

Each scene emits `answer_submitted` only from its explicit submit control, not on intermediate drag/tap. `set_interaction_enabled(false)` disables input while preserving visible state. `reset_state` returns to the configured question's initial state, and `apply_answer_state` rejects malformed/out-of-range state without partial mutation.

`AnswerInput` exposes `configure(question)`, `reset_state`, `set_interaction_enabled`, `get_answer_value`, and `answer_submitted(answer)`. Numeric keypad emits one integer; choice grid emits the selected typed option; factor slots emits an `integer_list` with the package's `order_matters` value. `ActivityRun` asks `AdaptiveBandSelector` for a band using the profile toggle and same-version recent events, looks up only the two allowlisted factories, places returned nodes in named container hosts, connects their common signal, and uses `QuestionEngine`/`RunSession`; it contains no switch on activity ID, math formula, reward rule, or Korean copy.

- [ ] **Step 5: Run scene tests at three portrait sizes**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite manipulatives`

Expected: contract, state round-trip, malformed-state, submission, all-eleven-activity host, and unclipped-layout checks pass at 360×800, 1080×2400, and 800×1280.

- [ ] **Step 6: Commit**

```bash
git add src/game/manipulatives src/ui/game/answer_inputs src/ui/game/answer_input_factory.gd src/ui/game/activity_run.gd tests/manipulatives
git commit -m "feat(game): host data-driven activities and manipulatives"
```

### Task 10: Convert Pinned Legacy CSV into Development Fixtures

**Files:**

- Create: `tools/content/legacy/legacy_types.ts`
- Create: `tools/content/legacy/legacy_expression.ts`
- Create: `tools/content/legacy/parse_legacy_csv.ts`
- Create: `tools/content/legacy/convert_legacy.ts`
- Create: `tools/content/fixtures/legacy/README.md`
- Create: `tools/content/fixtures/legacy/quiz_game_11.csv`
- Create: `tools/content/fixtures/legacy/quiz_game_7.csv`
- Create: `tools/content/fixtures/legacy/quiz_game_4.csv`
- Create: `tools/content/fixtures/legacy/quiz_game_9.csv`
- Create: `tools/content/fixtures/legacy/quiz_game_8_1.csv`
- Create: `tools/content/fixtures/legacy/expected_conversion.json`
- Test: `packages/contracts/test/tools/legacy_converter.test.ts`
- Test: `tests/content/legacy_expression_parity_test.gd`

**Interfaces:**

- Consumes: Task 4 expression grammar and Tasks 6–7 generator parameter contracts.
- Produces: Development-only `convertLegacyCsv(text, sourceName) -> ActivityPackageDraftV1` and five pinned compatibility fixtures.

- [ ] **Step 1: Add failing parser/translation tests**

Cover UTF-8 BOM, `[level]`, `[field,min,max]`, repeated ranged fields, components, `(sub_level)`, `(answer)`, question-format tokens, and translations `Mod[A+E~10] -> mod(A+E,10)`, `Quotient[X~Y] -> quotient(X,Y)`, `digit[answer~3] -> digit(answer,3)`, `gcd[X~Y]`, and `lcm[X~Y]`. Reject malformed ranges, duplicate levels, unbalanced delimiters, unsupported legacy functions, and cells that would become executable syntax.

- [ ] **Step 2: Run red converter tests**

Run: `npm run test:content-tools -- --run test/tools/legacy_converter.test.ts`

Expected: FAIL because the legacy modules and pinned fixtures do not exist.

- [ ] **Step 3: Add the five fixtures with immutable provenance**

`README.md` records repository, exact commit, original paths, SHA-256 for each copied CSV, retrieval date `2026-07-21`, and states that fixtures are development/test data only. Verify each file against GitHub at the pinned commit before committing; never copy legacy raster assets.

- [ ] **Step 4: Implement parsing and conversion**

Use a state machine and literal field maps, not regex evaluation. Map files exactly: `quiz_game_11` to addition, `quiz_game_7` to subtraction, `quiz_game_4` to multiplication, `quiz_game_9` to common-multiple/LCM, and `quiz_game_8_1` to prime factorization. Preserve meaningful level/range constraints as intro/practice/challenge generator parameters and preserve legacy equations only as compatibility assertions, not runtime content.

- [ ] **Step 5: Run converter and Godot expression parity tests**

Run: `npm run test:content-tools -- --run test/tools/legacy_converter.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: five conversions match `expected_conversion.json`; representative legacy expressions and new canonical expressions produce identical answers.

- [ ] **Step 6: Commit**

```bash
git add tools/content/legacy tools/content/fixtures packages/contracts/test/tools tests/content
git commit -m "feat(content): convert pinned legacy activity fixtures"
```

### Task 11: Author and Validate the Five Migrated Activity Sources

**Files:**

- Create: `content/sources/addition_ones.json`
- Create: `content/sources/subtraction_ones.json`
- Create: `content/sources/multiplication.json`
- Create: `content/sources/common_multiples_lcm.json`
- Create: `content/sources/prime_factorization.json`
- Create: `tools/content/independent_verify.ts`
- Test: `packages/contracts/test/content/migrated_packages.test.ts`
- Test: `tests/content/migrated_activity_golden_test.gd`

**Interfaces:**

- Consumes: Converter output as evidence, package schema, five generators, A effect preset IDs.
- Produces: Five human-reviewed `1.0.0` source drafts with three bands and four fixed validation seeds per band.

- [ ] **Step 1: Write failing package and golden tests**

For each activity, assert Korean title/description/tutorial, three hearts, configured goal/timer/rewards/effects, three ordered bands, adaptive off, known icon/layout/manipulative IDs, four samples per band, and independent mathematical answer verification. Golden tests compare seeds `1`, `7`, `42`, `20260721` with the pinned converter's representative operands/answers.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/migrated_packages.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL because the five activity sources do not exist.

- [ ] **Step 3: Author exact band intent**

Addition/subtraction intro isolate ones digits, practice uses two-digit operations, challenge uses three-to-five-digit column layouts. Multiplication intro uses one-by-one digit, practice two-by-one digit, challenge two-by-two digit. LCM intro uses two small operands, practice two broader operands, challenge three operands. Prime factorization grows factor count and allowed primes across bands. Each source uses only its generator parameters; no legacy display token or expression is copied into runtime data.

- [ ] **Step 4: Generate and independently verify samples**

`independent_verify.ts` recomputes arithmetic directly, LCM through prime exponent maps, and factorization by primality/product checks without calling the generator's answer helper. It fails any mismatch with activity/band/seed/resolved parameters.

- [ ] **Step 5: Run migrated activity suites**

Run: `npm run test:contracts -- --run test/content/migrated_packages.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: 60 fixed validation samples plus 15,000 property samples pass in TypeScript and Godot.

- [ ] **Step 6: Commit**

```bash
git add content/sources tools/content/independent_verify.ts packages/contracts/test/content/migrated_packages.test.ts tests/content
git commit -m "feat(content): author five migrated activities"
```

### Task 12: Author and Validate the Foundations Pack

**Files:**

- Create: `content/sources/foundations_counting.json`
- Create: `content/sources/foundations_number_bonds.json`
- Create: `content/sources/foundations_ten_frame.json`
- Create: `content/sources/foundations_base_ten.json`
- Create: `content/sources/foundations_number_line.json`
- Create: `content/sources/foundations_basic_operations.json`
- Create: `content/locales/ko-KR.json`
- Test: `packages/contracts/test/content/foundations_packages.test.ts`
- Test: `tests/content/foundations_activity_scene_test.gd`

**Interfaces:**

- Consumes: Task 8 generators, Task 9 manipulatives, centralized localization contract.
- Produces: Six foundations source drafts and Korean copy keys used by all 11 activities.

- [ ] **Step 1: Write failing content and scene tests**

Assert each foundation activity supplies age-appropriate bounds, three bands, four fixed seeds per band, a visible text label for every icon/action, optional/skippable tutorial copy, timer disabling where allowed, replayable speaker dialogue ID, and the matching manipulative. Scene tests generate one question per band, configure the scene, apply the known correct state, submit, and compare with `correct_answer`.

- [ ] **Step 2: Run red tests**

Run: `npm run test:contracts -- --run test/content/foundations_packages.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite manipulatives`

Expected: FAIL because the six sources and Korean locale are absent.

- [ ] **Step 3: Author exact progression**

Counting covers 1–5, 1–10, 1–20; number bonds wholes 2–5, 2–10, 5–20; ten frames cover 0–5, 0–10, 0–20; base ten covers 10–49, 10–99, 100–999; number lines use 0–10 forward, 0–20 bidirectional, −10–30 bidirectional while answers remain age-appropriate; basic operations cover sums/differences within 10, within 20, and within 100 without negative results. Timers default off for counting/manipulative exploration and remain profile-disableable elsewhere.

- [ ] **Step 4: Centralize Korean copy**

`ko-KR.json` contains system prompt keys, manipulative action labels, speaker labels, correctness text, and all prompt templates. Validate interpolation arguments against generator prompt args and reject missing/extra tokens. No `.tscn` or `.gd` file contains Korean gameplay copy.

- [ ] **Step 5: Run full foundations tests and copy scan**

Run: `npm run test:contracts -- --run test/content/foundations_packages.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite manipulatives && ! rg -n "[가-힣]" src --glob '*.gd' --glob '*.tscn'`

Expected: 72 fixed samples, 18,000 property samples, manipulative submission tests, and the hard-coded Korean scan pass.

- [ ] **Step 6: Commit**

```bash
git add content/sources content/locales packages/contracts/test/content/foundations_packages.test.ts tests/content
git commit -m "feat(content): add seven-year-old foundations pack"
```

### Task 13: Build Immutable Packages and the Offline Manifest

**Files:**

- Create: `tools/content/build_content.ts`
- Create: `tools/content/validate_content.ts`
- Create: `tools/content/verify_all_samples.ts`
- Create: `content/packages/addition_ones/1.0.0.json`
- Create: `content/packages/subtraction_ones/1.0.0.json`
- Create: `content/packages/multiplication/1.0.0.json`
- Create: `content/packages/common_multiples_lcm/1.0.0.json`
- Create: `content/packages/prime_factorization/1.0.0.json`
- Create: `content/packages/foundations_counting/1.0.0.json`
- Create: `content/packages/foundations_number_bonds/1.0.0.json`
- Create: `content/packages/foundations_ten_frame/1.0.0.json`
- Create: `content/packages/foundations_base_ten/1.0.0.json`
- Create: `content/packages/foundations_number_line/1.0.0.json`
- Create: `content/packages/foundations_basic_operations/1.0.0.json`
- Create: `content/manifests/1.0.0.json`
- Create: `content/active-manifest.json`
- Test: `packages/contracts/test/tools/build_content.test.ts`
- Test: `tests/content/bundled_catalogue_test.gd`

**Interfaces:**

- Produces: The exact bundled files consumed by A and published/rolled back by C.

- [ ] **Step 1: Write red reproducibility and corruption tests**

Test clean build output, byte-identical second build, source-order independence, exactly 11 manifest entries, checksum verification, unknown/missing package rejection, path traversal rejection, corrupted package rejection, and atomic build staging that leaves the old bundle untouched on failure.

- [ ] **Step 2: Run red tool tests**

Run: `npm run test:content-tools -- --run test/tools/build_content.test.ts`

Expected: FAIL because bundle tools and outputs do not exist.

- [ ] **Step 3: Implement build and validation entry points**

`build_content.ts` reads sorted sources, validates, recomputes all fixed samples independently, writes checksummed packages to a staging directory, builds the manifest, validates the complete staging set, then atomically replaces generated outputs. `--check` performs the build in memory and exits nonzero if checked-in output differs. Timestamps come from explicit `--published-at`; the release command uses `2026-07-21T00:00:00.000Z` for reproducibility.

- [ ] **Step 4: Generate version 1.0.0**

Run: `npm run build:content -- --content-version 1.0.0 --manifest-version 1.0.0 --published-at 2026-07-21T00:00:00.000Z`

Expected: writes 11 packages, 33 bands, 132 fixed validation samples, immutable manifest `1.0.0`, and matching `active-manifest.json`.

- [ ] **Step 5: Validate Node and Godot consumption**

Run: `npm run validate:content && npm run build:content -- --check --content-version 1.0.0 --manifest-version 1.0.0 --published-at 2026-07-21T00:00:00.000Z && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: `Validated 11 activities, 33 bands, 132 samples; manifest checksum set valid`; drift check exits 0; Godot loads every package and reproduces all fixed samples.

- [ ] **Step 6: Commit**

```bash
git add tools/content content/packages content/manifests content/active-manifest.json packages/contracts/test/tools tests/content
git commit -m "build(content): bundle validated version 1.0.0"
```

### Task 14: Establish the Art Direction, SVG System, and Asset Admission Gate

**Files:**

- Modify: `package.json`
- Create: `docs/art/ART_DIRECTION.md`
- Create: `docs/art/MOA_CHARACTER_GUIDE.md`
- Create: `docs/art/ASSET_REVIEW.md`
- Create: `assets/asset-manifest.json`
- Create: `assets/source/prompts/README.md`
- Create: `tools/assets/asset_schema.ts`
- Create: `tools/assets/validate_assets.ts`
- Create: `tools/assets/validate_svg.ts`
- Create: `packages/contracts/test/tools/asset_validation.test.ts`
- Create: `ASSET_LICENSES.md`

**Interfaces:**

- Produces: `npm run validate:assets`, asset IDs/paths consumed by Task 1 allowlists, and an admission rule shared with D.

- [ ] **Step 1: Write failing provenance and SVG tests**

Fixtures must reject missing origin/license/redistribution fields, duplicate IDs, unlisted files, missing files, path traversal, SVG `<script>`, event attributes, remote references, embedded raster data, `<text>`, wrong viewBox, colors outside the palette, raster dimension/alpha mismatches, and release audio without confirmed rights.

- [ ] **Step 2: Run red tests**

Run: `npm run test:content-tools -- --run test/tools/asset_validation.test.ts`

Expected: FAIL because asset schema/validators and manifests do not exist.

- [ ] **Step 3: Document exact visual tokens and Moa invariants**

Use canonical canvas 1080×1920 and palette mint `#66D3B5`, sky `#76C8F0`, sand `#F4D9A4`, coral `#FF8A7A`, apple red `#E94B4B`, gold `#F6C453`, navy `#23415A`, cream `#FFF8E8`. Moa is a small warm-brown sea otter with cream muzzle/chest, rounded child-friendly proportions, navy explorer satchel, coral neckerchief, five-finger-safe simplified paws, consistent eye spacing/whiskers, and no embedded letters, numbers, brands, or changing costume.

- [ ] **Step 4: Define the manifest/license records**

Each asset record requires `id`, release `path`, `kind`, dimensions or audio format, `origin: original|generated-derived|third-party`, creator/tool, source/master path, prompt path when generated, SHA-256, license identifier, modifications, `redistribution: confirmed`, reviewer, review date, and math/text/transparency review flags. Candidate/audition files may be recorded with `release: false`; only confirmed records can appear in a release scene/content allowlist.

- [ ] **Step 5: Implement strict validators and root script**

Add `validate:assets` as `tsx tools/assets/validate_assets.ts --manifest assets/asset-manifest.json --licenses ASSET_LICENSES.md`. The validator scans all release asset directories, proves manifest/files are bijective, verifies hashes and technical metadata, and fails candidates/auditions referenced by release content.

- [ ] **Step 6: Run tests**

Run: `npm run test:content-tools -- --run test/tools/asset_validation.test.ts`

Expected: all invalid fixture cases fail for the named reason and a minimal confirmed fixture passes.

- [ ] **Step 7: Commit**

```bash
git add docs/art assets/asset-manifest.json assets/source/prompts tools/assets packages/contracts/test/tools/asset_validation.test.ts ASSET_LICENSES.md package.json
git commit -m "build(assets): add provenance and validation gates"
```

### Task 15: Author Project-Native UI Icons and Learning Graphics

**Files:**

- Create: `assets/ui/icons/activities/addition_ones.svg`
- Create: `assets/ui/icons/activities/subtraction_ones.svg`
- Create: `assets/ui/icons/activities/multiplication.svg`
- Create: `assets/ui/icons/activities/common_multiples_lcm.svg`
- Create: `assets/ui/icons/activities/prime_factorization.svg`
- Create: `assets/ui/icons/activities/foundations_counting.svg`
- Create: `assets/ui/icons/activities/foundations_number_bonds.svg`
- Create: `assets/ui/icons/activities/foundations_ten_frame.svg`
- Create: `assets/ui/icons/activities/foundations_base_ten.svg`
- Create: `assets/ui/icons/activities/foundations_number_line.svg`
- Create: `assets/ui/icons/activities/foundations_basic_operations.svg`
- Create: `assets/ui/icons/status/correct.svg`
- Create: `assets/ui/icons/status/wrong.svg`
- Create: `assets/ui/icons/status/heart.svg`
- Create: `assets/ui/icons/status/speaker.svg`
- Create: `assets/ui/learning/ten_frame.svg`
- Create: `assets/ui/learning/ten_rod.svg`
- Create: `assets/ui/learning/unit_cube.svg`
- Create: `assets/ui/learning/number_line_marker.svg`
- Test: `packages/contracts/test/tools/release_svg_set.test.ts`

**Interfaces:**

- Consumes: Task 14 palette/SVG gate.
- Produces: All allowlisted vector IDs needed by the 11 packages/manipulatives.

- [ ] **Step 1: Write the failing required-set test**

Assert the exact 19 files above exist, use `viewBox="0 0 128 128"` for icons or the documented learning-graphic viewBox, contain title/description accessibility metadata but no rendered `<text>`, contain no external/embedded raster resource, and are represented in both manifests.

- [ ] **Step 2: Run red SVG tests**

Run: `npm run test:content-tools -- --run test/tools/release_svg_set.test.ts`

Expected: FAIL listing all 19 missing SVG assets.

- [ ] **Step 3: Author the coherent motif set**

Use literal motifs: plus tiles, minus bridge, grouped dots for multiplication, overlapping multiple rings, factor tree, counted shells, split number-bond circles, filled ten frame, hundred/tens/ones blocks, arrowed number line, and paired plus/minus blocks. Status icons combine silhouette with check/cross/heart/speaker shapes. Use round 8px strokes, navy outlines, palette fills, 12px safe padding, and mathematically correct counts/marks.

- [ ] **Step 4: Register and visually review**

Add each SHA/license record as `origin: original`, render an SVG contact sheet at 1×/2×/3×, and record review for silhouette, math correctness, contrast on cream/sky backgrounds, and 48dp legibility.

- [ ] **Step 5: Run SVG and asset validation**

Run: `npm run test:content-tools -- --run test/tools/release_svg_set.test.ts && npm run validate:assets`

Expected: all 19 assets pass safe-SVG, palette, manifest, hash, and review gates.

- [ ] **Step 6: Commit**

```bash
git add assets/ui assets/asset-manifest.json ASSET_LICENSES.md docs/art/ASSET_REVIEW.md packages/contracts/test/tools/release_svg_set.test.ts
git commit -m "feat(assets): add native MathLand icon system"
```

### Task 16: Produce Reviewed Raster Art with the Built-In Image Workflow

**Files:**

- Create: `assets/source/prompts/moa-anchor-v1.md`
- Create: `assets/source/prompts/exploration-island-v1.md`
- Create: `assets/source/prompts/collection-shells-v1.md`
- Create: `assets/source/art/generated/moa-anchor-v1.png`
- Create: `assets/source/art/generated/exploration-island-v1.png`
- Create: `assets/source/art/generated/collection-shells-keyed-v1.png`
- Create: `assets/source/art/masters/moa-v1.kra`
- Create: `assets/source/art/masters/collection-shells-v1.kra`
- Create: `assets/art/moa/moa_neutral.png`
- Create: `assets/art/moa/moa_celebrate.png`
- Create: `assets/art/moa/moa_encourage.png`
- Create: `assets/art/moa/moa_point.png`
- Create: `assets/art/island/exploration_island_bg.png`
- Create: `assets/art/collection/collection_shells.png`
- Test: `packages/contracts/test/tools/raster_assets.test.ts`

**Interfaces:**

- Consumes: Task 14 art/provenance gate and imagegen skill rules.
- Produces: Four 1024×1024 transparent Moa poses, one 1080×1920 opaque island background, and one 2048×2048 transparent 12-item collection sheet.

- [ ] **Step 1: Write red raster technical/review tests**

Assert exact dimensions, sRGB PNG, alpha requirements, transparent corners for Moa/collection, fully opaque island edges, no file above 6 MiB, exact manifest hashes, generated prompt linkage, nonempty reviewer, and all review flags true.

- [ ] **Step 2: Run red raster tests**

Run: `npm run test:content-tools -- --run test/tools/raster_assets.test.ts`

Expected: FAIL listing six missing release raster files.

- [ ] **Step 3: Save exact built-in prompts before generation**

`moa-anchor-v1.md` contains:

```text
Use case: stylized-concept
Asset type: game character anchor concept
Primary request: an original friendly sea-otter math explorer named Moa for a Korean children's math game
Subject: small warm-brown sea otter, cream muzzle and chest, rounded child-friendly proportions, navy explorer satchel, coral neckerchief, calm welcoming smile, full body visible
Style/medium: polished warm 2D children's game illustration, clean navy outline, simple readable shapes
Composition/framing: one centered neutral front three-quarter pose with generous padding on a plain opaque sand background
Color palette: mint, sky, sand, coral, apple red, gold, navy, cream
Constraints: one character only; no text; no letters; no numbers; no equations; no logo; no watermark; no extra props; anatomically consistent paws and tail
Avoid: photorealism, baby costume, glossy 3D plastic, busy scenery
```

`exploration-island-v1.md` requests a 1080×1920 portrait warm exploration island with sea/coves/path clearings and safe UI negative space, no character/text/math marks/logos/watermark. `collection-shells-v1.md` requests exactly 12 distinct simple shell/star/pebble collectibles in a 4×3 grid on a perfectly flat solid `#ff00ff` key background, crisp separated edges, no shadows/text/watermark, and no magenta in subjects.

- [ ] **Step 4: Generate one built-in call per candidate and persist it**

Invoke built-in `image_gen` separately with each saved prompt. Inspect each result, select at most one candidate, and copy it from `$CODEX_HOME/generated_images/` to the exact `assets/source/art/generated/` path. Record tool mode `built-in image_gen`, final prompt file, generation date, and source SHA. Do not use CLI fallback.

- [ ] **Step 5: Create production masters and exports**

Use the approved Moa anchor only as a reference, redraw/clean the four consistent poses in `moa-v1.kra`, and export transparent PNGs; this avoids requesting model-native fur transparency. Clean the island candidate to the canonical portrait canvas with no baked UI. For the simple keyed collection sheet, run:

```bash
python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
  --input assets/source/art/generated/collection-shells-keyed-v1.png \
  --out assets/art/collection/collection_shells.png \
  --auto-key border --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill
```

If keyed removal fails or any proposed generated asset requires true/native transparency, pause execution and obtain explicit user approval before any CLI `gpt-image-1.5` use; manual master-sheet cleanup remains the default path.

- [ ] **Step 6: Review and register final art**

Review Moa identity across poses, exactly 12 collectible cells, mathematical/text absence, unwanted limbs/objects, child-appropriate expression, alpha fringe on cream/sky/navy test mats, 360px preview legibility, and island UI clearance. Record release assets as `generated-derived`, link their masters/prompts, and keep generated candidates `release: false`.

- [ ] **Step 7: Run raster and complete asset gates**

Run: `npm run test:content-tools -- --run test/tools/raster_assets.test.ts && npm run validate:assets`

Expected: six raster exports pass dimensions, alpha, size, provenance, rights, hash, and human-review gates; candidates are not referenced by release content.

- [ ] **Step 8: Commit**

```bash
git add assets/source/prompts assets/source/art assets/art assets/asset-manifest.json ASSET_LICENSES.md docs/art/ASSET_REVIEW.md packages/contracts/test/tools/raster_assets.test.ts
git commit -m "feat(assets): add reviewed Moa and island artwork"
```

### Task 17: Produce and Validate Offline Music, SFX, and Voice

**Files:**

- Create: `assets/source/audio/dialogue-ko-KR.csv`
- Create: `assets/source/audio/AUDIO_DELIVERY_SPEC.md`
- Create: `assets/audio/audio-manifest.json`
- Create: `assets/audio/music/exploration_loop.ogg`
- Create: `assets/audio/music/concentration_loop.ogg`
- Create: `assets/audio/music/boss_loop.ogg`
- Create: `assets/audio/sfx/button_down.ogg`
- Create: `assets/audio/sfx/button_release.ogg`
- Create: `assets/audio/sfx/correct.ogg`
- Create: `assets/audio/sfx/wrong.ogg`
- Create: `assets/audio/sfx/heart_loss.ogg`
- Create: `assets/audio/sfx/combo_1.ogg`
- Create: `assets/audio/sfx/combo_2.ogg`
- Create: `assets/audio/sfx/combo_3.ogg`
- Create: `assets/audio/sfx/boss.ogg`
- Create: `assets/audio/sfx/level_up.ogg`
- Create: `assets/audio/sfx/reward.ogg`
- Create: `assets/audio/sfx/manipulative_place.ogg`
- Create: `assets/audio/voice/ko-KR/moa_home_welcome.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_counting.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_number_bonds.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_ten_frame.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_base_ten.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_number_line.ogg`
- Create: `assets/audio/voice/ko-KR/moa_tutorial_basic_operations.ogg`
- Create: `assets/audio/voice/ko-KR/moa_reward.ogg`
- Create: `assets/audio/voice/ko-KR/moa_level_up.ogg`
- Create: `tools/assets/validate_audio.ts`
- Test: `packages/contracts/test/tools/audio_assets.test.ts`
- Test: `tests/content/audio_manifest_test.gd`

**Interfaces:**

- Consumes: A's Master/Music/SFX/Voice bus IDs and voice interruption API.
- Produces: Stable audio IDs, offline Ogg assets, loop metadata, and confirmed redistribution records.

- [ ] **Step 1: Write failing audio manifest/technical tests**

Assert exactly 3 music, 12 SFX, and 9 Korean voice files; 48kHz Ogg Vorbis; stereo music, mono SFX/voice; music loop points and seam delta below −50dBFS; SFX under 2.0s except level/reward under 4.0s; voice peak below −1dBFS and integrated loudness −18±2 LUFS; music −20±2 LUFS; no clipping; stable dialogue IDs; confirmed redistribution; and no audition/system-voice path in the release manifest.

- [ ] **Step 2: Run red audio tests**

Run: `npm run test:content-tools -- --run test/tools/audio_assets.test.ts`

Expected: FAIL listing all missing audio deliverables and validator.

- [ ] **Step 3: Lock dialogue and delivery requirements before recording**

`dialogue-ko-KR.csv` contains the nine IDs and approved short Korean lines for welcome, six foundation introductions, reward, and level-up. It also records pronunciation notes, maximum duration, skippable `true`, automatic-play policy, and speaker-control replay policy. Use an adult warm female guide voice; do not record a child. Question narration has no automatic clip and is triggered only by the speaker control.

- [ ] **Step 4: Acquire original/licensed source audio with written rights**

Commission or record the three seamless loops, twelve tactile SFX, and nine dialogue lines under terms that explicitly allow modification, bundling in the APK, redistribution through GitHub Releases, and indefinite product use. System/TTS auditions stay under an ignored `assets/source/audio/auditions/` directory and are never copied into `assets/audio/`. Record the rights document identifier and confirmation date in `ASSET_LICENSES.md`; do not commit contracts containing personal addresses/signatures.

- [ ] **Step 5: Normalize and encode deterministic release files**

Use FFmpeg with 48kHz output, Vorbis quality 5, stereo music, mono SFX/voice, loudness normalization targets above, trimmed leading silence under 80ms for SFX and 150ms for voice, and embedded loop metadata for music. Keep lossless source masters under `assets/source/audio/masters/` when redistribution permits; otherwise record source checksum and secured archive location without committing it.

- [ ] **Step 6: Implement ffprobe/decoded-wave validation and register assets**

`validate_audio.ts` calls `ffprobe` with JSON output, decodes loop head/tail for seam analysis, verifies duration/channel/rate/loudness/peak, cross-checks manifest IDs and A's bus IDs, and rejects rights states other than `confirmed`. `audio-manifest.json` maps every ID to path, bus, autoplay policy, replayable/skippable flags, loop points, locale, and license record.

- [ ] **Step 7: Run audio, asset, and Godot manifest tests**

Run: `npm run test:content-tools -- --run test/tools/audio_assets.test.ts && npm run validate:assets && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: 24 audio files pass technical/rights checks; Godot resolves every manifest ID to the correct bus and confirms question input is never blocked by voice.

- [ ] **Step 8: Commit**

```bash
git add assets/source/audio/dialogue-ko-KR.csv assets/source/audio/AUDIO_DELIVERY_SPEC.md assets/audio tools/assets/validate_audio.ts assets/asset-manifest.json ASSET_LICENSES.md packages/contracts/test/tools/audio_assets.test.ts tests/content/audio_manifest_test.gd
git commit -m "feat(audio): add licensed offline MathLand sound set"
```

### Task 18: Complete Subproject B Integration, Documentation, and Handoff

**Files:**

- Create: `docs/content/CONTENT_AUTHORING.md`
- Create: `docs/content/LEGACY_CONVERSION.md`
- Create: `docs/content/PACKAGE_OPERATIONS.md`
- Create: `docs/assets/ASSET_PRODUCTION.md`
- Create: `tests/content/content_pipeline_acceptance_test.gd`
- Create: `packages/contracts/test/content/pipeline_acceptance.test.ts`
- Modify: `.github/workflows/ci.yml`
- Modify: `README.md`

**Interfaces:**

- Consumes: All B outputs and A/C/D shared contracts.
- Produces: Independently testable version `1.0.0` content/art/audio deliverable and exact integration commands for C/D.

- [ ] **Step 1: Write the failing end-to-end acceptance tests**

TypeScript builds/validates from a clean temporary directory, loads all 11 packages, generates all 132 fixed samples, independently verifies answers, and proves a corrupt checksum/unknown resource cannot replace the active manifest. Godot loads the active manifest, generates one question from every band, configures any manipulative, submits the known correct state, and asserts the activity/content/generator/band/seed/resolved-parameter envelope is intact.

- [ ] **Step 2: Run red acceptance tests**

Run: `npm run test:contracts -- --run test/content/pipeline_acceptance.test.ts && /opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content`

Expected: FAIL until acceptance fixtures, documentation links, and CI jobs are wired.

- [ ] **Step 3: Document authoring and operational procedures**

Document exact source fields and generator parameters, fixed/adaptive behavior, Korean copy interpolation, validation samples, semver/checksum semantics, adding a generator/manipulative, converter provenance, build/validation commands, Content Studio draft/publish/rollback contract, cache fallback, imagegen built-in-first workflow, transparent candidate rules, SVG review, audio delivery/rights, and failure diagnosis. Include concrete valid/invalid package excerpts and never include credentials or real service URLs.

- [ ] **Step 4: Add CI gates**

CI installs locked npm dependencies, runs contracts/tools/content build drift, runs asset/audio validators with FFmpeg installed, then runs Godot `content` and `manipulatives` suites. It fails on changed generated packages, unknown assets, unconfirmed rights, legacy raster references, skipped content tests, or nonzero test exits.

- [ ] **Step 5: Run the full Subproject B gate**

Run:

```bash
npm ci
npm run test:contracts
npm run test:content-tools
npm run validate:content
npm run build:content -- --check --content-version 1.0.0 --manifest-version 1.0.0 --published-at 2026-07-21T00:00:00.000Z
npm run validate:assets
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite content
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite manipulatives
```

Expected: all commands exit 0; validator reports 11 activities, 33 bands, 132 fixed samples; every release asset has confirmed rights/provenance; both Godot suites report zero failures.

- [ ] **Step 6: Verify scope and secrets**

Run: `! rg -n "com\.example\.test3|192\.168\.|service_role|OPENAI_API_KEY|SUPABASE_SERVICE_ROLE_KEY" content src/content src/game/manipulatives assets/art assets/ui assets/audio && ! find assets -type f \( -iname '*legacy*' -o -iname '*.apk' -o -iname '*.jks' -o -iname '*.keystore' \) -print -quit | grep .`

Expected: both negative scans exit 0; no legacy identity/raster, development host, privileged key name in shipped content, APK, or signing material is present in B outputs.

- [ ] **Step 7: Commit**

```bash
git add docs/content docs/assets tests/content packages/contracts/test/content .github/workflows/ci.yml README.md
git commit -m "docs(content): complete pipeline operations and gates"
```

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-21-content-asset-pipeline.md`. Execute with one of these modes:

1. **Subagent-Driven (recommended):** use `superpowers:subagent-driven-development`, dispatch a fresh worker for each task, and perform specification then code-quality review before advancing.
2. **Inline Execution:** use `superpowers:executing-plans`, execute in reviewable batches, and stop at the explicit asset-rights or true-transparency approval gates.
