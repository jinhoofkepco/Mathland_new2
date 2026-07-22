# Release Art Corrections Design

## Goal

Correct the reviewed release artwork and make the admitted release assets visible in the Godot runtime through one deterministic manifest-ID contract, while preserving translated labels and accessibility text.

## Asset geometry

- `foundations_base_ten.svg` will show a square hundred flat split into exactly ten columns and ten rows, a ten rod split into exactly ten equal sections, and two unit cubes. The major silhouettes and partitions must remain readable at a 48px target.
- `foundations_number_line.svg` will show four equally spaced ticks and exactly three separate, equal-width hop arcs from the first tick to the fourth.
- TypeScript regression checks will inspect the SVG structure and numeric geometry rather than relying on descriptions or review flags.

## Runtime asset contract

- A focused `AssetCatalog` Godot class will be the sole mapping from public asset-manifest IDs to `res://` release paths.
- The catalog will also map content activity IDs to manifest activity-icon IDs. For the current vertical slice, `foundation_ten_rods` resolves to `ui.activity.foundations_base_ten`.
- The exploration island will load `art.island.exploration_bg` through the catalog and display it behind the existing child-shell UI.
- The collection screen will load `art.collection.shells` through the catalog and display deterministic atlas regions for collection entries, with a safe fallback for unknown entries.
- Tactile buttons will accept explicit manifest icon IDs, display release SVG textures when known, and keep their visible `TextLabel`, accessibility name, accessibility description, tooltip, and glyph fallback.
- Free-play activity controls will resolve the activity icon from the content activity ID through the same catalog. No runtime file will reference `assets/source/`.

## Generated-art provenance

- Each Moa release pose will link to a pose-specific saved generation prompt and a pose-specific non-release source/master PNG under `assets/source/art/generated/`.
- The source/master path must differ from the release output path. Its manifest record, hash, prompt hash, generation date, and license entry will make the chain independently auditable.
- The island release record and review documentation will explicitly declare the proportional resize from 941×1672 to 1080×1920 and the sRGB metadata write; it will not call the operation a crop or claim unchanged pixels.

## Validation and failure behavior

- Asset validation will reject release runtime records that are not referenced through the public catalog, inconsistent activity-to-manifest mappings, self-aliased generated masters, pose prompt reuse, prompt/source stem mismatches, and inaccurate declared raster transformations.
- Runtime catalog lookups return an empty path or fallback glyph/collection region for unknown IDs, so missing optional art never removes actionable text.
- Focused Godot scene tests will assert that the island background, collection texture regions, and tactile SVG icons instantiate while visible/accessibility labels remain populated.

## Verification

Run the asset-focused Vitest files, `npm run validate:assets`, the contracts TypeScript typecheck, and the Godot scene tests covering tactile buttons and child-shell island/collection screens. Finish with a clean diff review that excludes generated `.uid` and `.import` files.
