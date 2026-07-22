# Release Art Corrections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the reviewed SVG mathematics and generated-art provenance, then expose the admitted island, collection, activity, and control assets through one accessible Godot runtime catalog.

**Architecture:** `AssetCatalog` owns deterministic manifest-ID-to-release-path and content-ID-to-manifest-ID mappings. TypeScript asset tests inspect mathematical geometry, provenance chains, transformation metadata, and static runtime references; Godot scene tests prove the mapped textures instantiate without replacing translated or accessibility text.

**Tech Stack:** Godot 4.7.1 typed GDScript, SVG/PNG, TypeScript 5, Vitest, Zod 4, Node SHA-256, and the repository-owned asset/Godot test runners.

## Global Constraints

- Work only in the existing `.worktrees/assets-art` linked worktree based on `580f64b742d006f449792dccd9d585f6d6c01093`.
- Preserve every SVG `<title>`, `<desc>`, and `aria-labelledby="title desc"` accessibility field.
- Runtime code may reference only release assets under `assets/art/` and `assets/ui/`; it may never reference `assets/source/`.
- Keep tactile visible labels, `accessibility_name`, `accessibility_description`, tooltip text, and glyph fallback even when a texture icon is available.
- `foundation_ten_rods` maps exactly to manifest ID `ui.activity.foundations_base_ten`.
- The island transformation is an exact Pillow Lanczos resize from 941×1672 to 1080×1920 followed by explicit sRGB metadata; it is not a crop and did change the encoded release pixels.
- The four restored Moa sources must match their original built-in `image_gen` outputs: neutral `bb91c5ee4b3f3e94d2bb8ad17dd4ccd6cbcd4c6487f40038d7d224c4dce5135f`, celebrate `e2cea9f78f11723c25b1fb43a4b14d6220c61e34125431d679ae59830313cd82`, encourage `0386818ca4e3a0b1ad71eb6956ff32be1bbdea419bea4251e2b5c7f19a5ef56a`, and point `524572f4a3553caa6ef79644c32072c2b4bc4b5bbdaafca0e0c4532ae336bef3`.
- Do not stage Godot-generated `.uid` or `.import` files.

---

### Task 1: Make the Foundation SVG Mathematics Exact

**Files:**

- Modify: `packages/contracts/test/tools/release_svg_set.test.ts`
- Modify: `assets/ui/icons/activities/foundations_base_ten.svg`
- Modify: `assets/ui/icons/activities/foundations_number_line.svg`
- Modify: `assets/asset-manifest.json`

**Interfaces:**

- Consumes: SVG `viewBox="0 0 128 128"` and the canonical palette.
- Produces: a square 10×10 hundred flat, a ten-section rod, and three separate equal number-line hop paths.

- [ ] **Step 1: Write geometry assertions before editing either SVG**

Add numeric SVG helpers that extract elements by class and assert:

```ts
expect(columnDividers).toHaveLength(9);
expect(rowDividers).toHaveLength(9);
expect(flat.width).toBe(flat.height);
expect(unitCubes).toHaveLength(2);
expect(rodDividers).toHaveLength(9);
expect(hops).toHaveLength(3);
expect(hops.map(({ from, to }) => to - from)).toEqual([24, 24, 24]);
expect(hops.map(({ from, to }) => [from, to])).toEqual([[24, 48], [48, 72], [72, 96]]);
```

- [ ] **Step 2: Run the focused SVG test and verify red**

Run: `npm --workspace @mathland/contracts test -- test/tools/release_svg_set.test.ts`

Expected: FAIL because the hundred flat has neither a square 10×10 grid nor nine dividers per axis, the rod has only four internal dividers, and the number line contains two unequal hop paths.

- [ ] **Step 3: Author the minimal exact geometry**

Use nine equal-spaced vertical and nine equal-spaced horizontal `<line>` elements inside one square flat; use nine equal-spaced horizontal `<line>` elements inside the rod; retain two unit-cube rectangles. Replace the combined number-line arcs with three `class="number-line-hop"` paths spanning 24→48, 48→72, and 72→96 at identical height and curvature. Keep the existing title and description text.

- [ ] **Step 4: Update only the two changed SVG SHA-256 values and verify green**

Run: `npm --workspace @mathland/contracts test -- test/tools/release_svg_set.test.ts`

Expected: 4 SVG-set tests pass, including exact base-ten and three-hop geometry.

### Task 2: Restore Exact Pose Provenance and Declare Raster Transformations

**Files:**

- Modify: `packages/contracts/test/tools/asset_validation.test.ts`
- Modify: `packages/contracts/test/tools/raster_assets.test.ts`
- Modify: `tools/assets/asset_schema.ts`
- Modify: `tools/assets/validate_assets.ts`
- Create: `assets/source/prompts/moa-neutral-v1.md`
- Create: `assets/source/prompts/moa-celebrate-v1.md`
- Create: `assets/source/prompts/moa-encourage-v1.md`
- Create: `assets/source/prompts/moa-point-v1.md`
- Create: `assets/source/art/generated/moa-neutral-v1.png`
- Create: `assets/source/art/generated/moa-celebrate-v1.png`
- Create: `assets/source/art/generated/moa-encourage-v1.png`
- Create: `assets/source/art/generated/moa-point-v1.png`
- Modify: `assets/source/prompts/README.md`
- Modify: `assets/asset-manifest.json`
- Modify: `ASSET_LICENSES.md`
- Modify: `docs/art/ASSET_REVIEW.md`
- Modify: `docs/art/MOA_CHARACTER_GUIDE.md`

**Interfaces:**

- Consumes: four original 1254×1254 RGB built-in-image-generation outputs and their exact saved prompt strings recovered from the generation session.
- Produces: one unique non-release source record and prompt hash for every Moa release, plus structured source/output dimensions and operation lists for every generated release PNG.

- [ ] **Step 1: Write failing provenance and transformation tests**

Assert that generated PNG releases reject `master_path === path`, that transformation source/output dimensions must match the linked source and release records, and that all four Moa releases have distinct prompt/source/master paths whose prompt and source stems match the pose. Assert the island transformation is exactly 941×1672→1080×1920 with `resize-lanczos` and `add-srgb-chunk`, and its prose contains `resize` but neither `crop` nor `without pixel changes`.

- [ ] **Step 2: Run focused tests and verify red**

Run: `npm --workspace @mathland/contracts test -- test/tools/asset_validation.test.ts test/tools/raster_assets.test.ts`

Expected: FAIL because all poses reuse the anchor prompt/source, generated release masters alias release outputs, and no structured transformation declaration exists.

- [ ] **Step 3: Add strict transformation/linkage validation**

Add this required shape for generated release PNGs:

```ts
transformation: {
  source_width: number;
  source_height: number;
  output_width: number;
  output_height: number;
  operations: string[];
}
```

Validation must emit `GENERATED_MASTER_INVALID` when a master aliases or points to a release record and `RASTER_TRANSFORMATION_INVALID` when declared dimensions differ from linked records.

- [ ] **Step 4: Restore the original sources and exact prompt files**

Copy the four original generated outputs into the four pose-specific source paths and verify their pinned SHA-256 values from Global Constraints. Save the exact neutral, celebration, encouragement, and pointing generation prompts verbatim in the corresponding Markdown files.

- [ ] **Step 5: Rebuild the manifest provenance chains**

Register four non-release source records. Point each `art.moa.*` release `source_path`, `master_path`, `prompt_path`, and prompt hash at its same-pose source/prompt. Point island and collection masters at their genuine non-release sources. Declare exact operations: Moa chroma-key/despill, RGBA conversion, 1254→1024 Lanczos resize, optimized PNG, and sRGB chunk; island 941×1672→1080×1920 Lanczos resize, optimized PNG, and sRGB chunk; collection chroma-key/despill, resize, transparent padding, optimized PNG, and sRGB chunk.

- [ ] **Step 6: Correct prose and verify green**

Update prompt index, licenses, Moa guide, and review record to state the real pose-specific chain and exact island resize. Run the two focused Vitest files and `npm run validate:assets`; expect no issues.

### Task 3: Add the Canonical Runtime Asset Catalog

**Files:**

- Create: `packages/contracts/test/tools/runtime_asset_integration.test.ts`
- Create: `src/presentation/assets/asset_catalog.gd`
- Modify: `src/presentation/controls/tactile_button.gd`
- Modify: `scenes/shared/tactile_button.tscn`
- Modify: `src/ui/shared/mathland_ui.gd`
- Modify: `src/ui/island/exploration_island.gd`
- Modify: `src/ui/island/collection.gd`
- Modify: `src/ui/island/free_play.gd`
- Modify: `src/ui/game/activity_run.gd`
- Modify: `src/game/manipulatives/ten_rod_board.gd`
- Modify: `src/ui/profile/profile_create_dialog.gd`
- Modify: `tests/scene/test_tactile_button.gd`
- Modify: `tests/scene/test_child_shell_screens.gd`
- Create: `tests/unit/test_asset_catalog.gd`

**Interfaces:**

- Consumes: public manifest IDs and content activity ID `foundation_ten_rods`.
- Produces: `AssetCatalog.path_for(asset_id) -> String`, `texture_for(asset_id) -> Texture2D`, `activity_icon_id(activity_id) -> StringName`, and `collection_region(entry_id) -> Rect2`.

- [ ] **Step 1: Write static and live runtime regression tests**

Read the manifest, catalog, content JSON, and consumer scripts. Assert exact manifest-ID/path pairs for island, collection, activity base-ten, correct, wrong, heart, and speaker assets; assert `foundation_ten_rods` maps to `ui.activity.foundations_base_ten`; assert island, collection, free-play, and tactile code call the catalog; assert all runtime consumers remain free of `assets/source/`.

In Godot, assert the catalog resolves exact release paths and returns empty for unknown IDs; a tactile button configured with `ui.status.correct` displays `%IconTexture` while its `TextLabel`, `accessibility_name`, `accessibility_description`, and tooltip remain `다음`; exploration island contains a textured `ExplorationIslandBackground`; collection `first_map` contains an atlas-backed `CollectionArt_first_map` and its translated name.

- [ ] **Step 2: Run TypeScript and Godot runtime tests and verify red**

Run: `npm --workspace @mathland/contracts test -- test/tools/runtime_asset_integration.test.ts && ./tools/test/run_godot_tests.sh unit && ./tools/test/run_godot_tests.sh scene`

Expected: FAIL because `asset_catalog.gd`, its mapped textures, and the new runtime nodes do not exist.

- [ ] **Step 3: Implement the deterministic catalog**

Create immutable dictionaries of exact manifest IDs to `res://` paths and `foundation_ten_rods` to `ui.activity.foundations_base_ten`. Return empty values for unknown IDs. Define the collection atlas as a 4×3 grid of 480px cells beginning at `(64, 304)` on the 2048px sheet.

- [ ] **Step 4: Wire island and collection art**

Add a full-rect, aspect-covered `TextureRect` named `ExplorationIslandBackground` behind the safe UI. Replace the collection star for known entries with an `AtlasTexture`-backed `TextureRect` named `CollectionArt_<entry_id>`; keep the translated collection name and star fallback for unknown entries.

- [ ] **Step 5: Wire tactile and activity icons without removing text**

Add `%IconTexture` beside `%IconLabel`. Resolve explicit manifest IDs through the catalog; show the SVG texture when known and the existing glyph when unknown. Free play obtains the activity manifest ID through `activity_icon_id`; speaker and check controls pass `ui.status.speaker` and `ui.status.correct` explicitly. Do not change label translation/accessibility assignment.

- [ ] **Step 6: Run TypeScript and Godot runtime tests and verify green**

Run: `npm --workspace @mathland/contracts test -- test/tools/runtime_asset_integration.test.ts && ./tools/test/run_godot_tests.sh unit && ./tools/test/run_godot_tests.sh scene`

Expected: all mapping, rendering, and preserved-accessibility assertions pass with no `SCRIPT ERROR` output.

### Task 4: Full Verification and Commit

**Files:** all files above.

**Interfaces:** Produces one reviewable release-art correction branch.

- [ ] **Step 1: Run the complete requested verification set**

```bash
npm --workspace @mathland/contracts test -- test/tools/asset_validation.test.ts test/tools/raster_assets.test.ts test/tools/release_svg_set.test.ts test/tools/runtime_asset_integration.test.ts
npm run validate:assets
npm --workspace @mathland/contracts run typecheck
./tools/test/run_godot_tests.sh unit
./tools/test/run_godot_tests.sh scene
```

- [ ] **Step 2: Review repository state**

Run `git diff --check`, inspect `git diff --stat`, verify every requested finding against the spec, and ensure `.uid`/`.import` files remain untracked and unstaged.

- [ ] **Step 3: Commit the implementation**

Stage only the planned source, asset, test, and documentation files and commit with `fix(assets): correct release art integration`.
