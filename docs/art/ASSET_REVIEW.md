# Asset Review Record

Reviewer: `Codex visual review`  
Review date: `2026-07-21`  
Release rights: confirmed by the project owner for original project-native vectors and original user-directed generated work.

## SVG review

All 19 required UI/activity/status/learning SVGs were rendered as contact sheets at 1×, 2×, and 3×, then inspected again at a 48px target. Source colors and navy silhouettes were checked against both cream and sky palette backgrounds. The review found no rendered text, remote/raster payload, unsafe event/script content, clipped silhouette, or color-only status cue.

| Group | Assets | Mathematical/silhouette result |
| --- | --- | --- |
| Migrated activities | addition, subtraction, multiplication, common multiples, prime factorization | Two addends meet; five tiles include two moving away; three equal groups contain two dots each; two multiple rings share a gold point; the factor tree branches consistently |
| Foundations | counting, number bonds, ten frame, base ten, number line, basic operations | Five countable objects; one whole/two parts; exactly seven row-major counters; hundred/ten/two units; rightward equal hops; distinct plus/minus pair |
| Status | correct, wrong, heart, speaker | Check, cross, heart silhouette, and sound-wave shape remain distinct at 48px |
| Learning | ten frame, ten rod, unit cube, number-line marker | Seven occupied frame cells; exactly ten rod partitions; one cube; marker aligns to a visible tick |

Review flags for every SVG manifest record are: math correct, text absent, transparency correct, artifacts absent, child appropriate, silhouette clear, contrast checked, and legible at 48dp.

## Raster review

| Asset set | Visual review | Technical review |
| --- | --- | --- |
| Four Moa poses | Identity, eye/muzzle/whisker continuity, coral scarf, navy satchel, paws/limbs, child-appropriate expressions, no text/math/logo/watermark | 1024×1024 RGBA; transparent corners; 360px preview legibility; each below 6 MiB |
| Exploration island | Portrait path flow, clear activity clearings, top/bottom UI clearance, no character/text/math mark/logo/watermark | 1080×1920 RGB; fully opaque; sRGB; below 6 MiB |
| Collection sheet | Exactly 12 separated objects in a 4×3 grid; no duplicates, text, extra props, or visible key-color fringe on cream/sky/navy mats | 2048×2048 RGBA; transparent corners; 1920×1440 preserved grid centered with padding; below 6 MiB |

The Moa and island release pixels were retained while an explicit PNG sRGB chunk was added. The collection source was alpha-cleaned before this task, then resized once with Pillow Lanczos and padded on a transparent production canvas. The generated candidates remain `release: false`; runtime reference scanning rejects `assets/source/` paths.

## Provenance review

- Creator/tool for generated candidates and derived releases: `OpenAI built-in image_gen`.
- Prompts and source candidates are linked by exact paths and SHA-256 values.
- License: `MathLand-Generated-Original-1.0`; original user-directed generated work; redistribution confirmed.
- Project-native SVG license: `MathLand-Original-1.0`; redistribution confirmed.
- No fake `.kra` master is present. Checked-in production PNGs are declared as production masters until a genuine editable authoring file exists.
