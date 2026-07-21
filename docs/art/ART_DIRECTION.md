# MathLand Art Direction

MathLand is a warm portrait-first exploration game for early elementary mathematics. The visual hierarchy must make the next touch obvious, make mathematical quantities readable before decoration, and keep feedback energetic without becoming noisy.

## Canvas and layout

- Canonical scene canvas: 1080×1920 portrait.
- Phone portrait is the primary target; tablet portrait expands safe margins and content spacing rather than stretching artwork.
- Keep important faces, activity nodes, and manipulatives inside the central 864×1536 safe area. Preserve calm negative space above and below the island for runtime UI.
- Icons use `viewBox="0 0 128 128"` with at least 12 units of silhouette padding. Learning graphics use `viewBox="0 0 256 256"`.
- Minimum interactive target is 48dp. Details that disappear at 48dp are supporting texture, never the sole cue.

## Canonical palette

| Token | Hex | Use |
| --- | --- | --- |
| Mint | `#66D3B5` | progress, groups, positive secondary fill |
| Sky | `#76C8F0` | exploration, guidance, neutral quantity fill |
| Sand | `#F4D9A4` | grounded surfaces and warm neutral fills |
| Coral | `#FF8A7A` | interaction, movement, recoverable error |
| Apple red | `#E94B4B` | hearts, counters, high-attention state |
| Gold | `#F6C453` | rewards, shared points, highlights |
| Navy | `#23415A` | outlines, symbols, structural contrast |
| Cream | `#FFF8E8` | panels, negative space, light symbol fill |

Project-native SVGs use only these literal colors. Raster illustration may use tonal variations needed for volume, but its focal colors must remain recognizably aligned with the palette.

## Shape and line language

- Primary icon outlines are navy, round, and nominally 8 units on a 128-unit icon canvas.
- Use rounded corners, round caps, and round joins. Avoid sharp danger silhouettes and glossy plastic rendering.
- Never communicate correct/wrong, filled/empty, or direction by color alone. Pair color with a check, cross, occupancy, arrow, silhouette, or position.
- Mathematical graphics take precedence over ornament. Counts, row-major occupancy, equal groups, factor branches, place-value partitions, and line endpoints must remain mathematically true.
- SVG accessibility metadata consists of a nonempty `title#title`, `desc#desc`, and `aria-labelledby="title desc"`. Rendered `<text>` is forbidden so localization remains in the UI layer.

## Raster language

Moa and the island use polished warm 2D children's illustration with clean navy-edged forms, gentle texture, readable silhouettes, and bright morning light. Production exports are explicit sRGB PNG files. Moa and collection exports have transparent corners; the island is fully opaque. A release raster must remain under 6 MiB.

## Motion and game feel

- Touch-down feedback begins immediately with scale, light, and a short sound; completion effects follow the mathematical event rather than obscuring it.
- Correct feedback expands from the selected answer and resolves toward the progress target. Wrong feedback uses a brief coral pulse and heart transition, never a punitive screen shake.
- Reserve larger particle bursts for streak milestones, stage completion, restoration, and collection unlocks.
- Respect reduced-motion settings by replacing travel and bounce with short opacity/color transitions.

## Admission boundary

`npm run validate:assets` is the release gate. It enforces strict manifest fields, normalized repository paths, a manifest/filesystem bijection, SHA-256 integrity, license-ledger coverage, redistribution confirmation, review flags, safe SVG structure and palette, PNG dimensions/color space/alpha/size, and generated prompt/source linkage. Files under `assets/source/` are provenance inputs and may never be referenced directly by runtime scenes or content.
