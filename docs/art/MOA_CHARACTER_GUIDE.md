# Moa Character Guide

Moa is MathLand's primary guide: a small warm-brown sea otter and calm math explorer. Moa supports the child, celebrates effort, and points toward the next action without speaking over the problem.

## Identity invariants

- Warm-brown coat with a cream muzzle and chest.
- Rounded, child-friendly head and body proportions; full tail remains visible when the pose permits.
- Stable eye spacing, small dark nose, short whiskers, and the same cream muzzle construction in every pose.
- Navy explorer satchel worn on the same diagonal, with mint trim and a simple gold clasp.
- Coral neckerchief tied at the front. Costume, accessories, and color placement do not change between poses.
- Simplified paws are anatomically readable and five-finger-safe: no extra limbs, fused accidental paws, or sharp claws.
- No embedded letters, numbers, equations, brands, logos, or watermarks.

## Pose set

| Asset | Intent | Silhouette rule |
| --- | --- | --- |
| `art.moa.neutral` | Quiet listening and profile/island idle | Both feet grounded; hands rest near the satchel |
| `art.moa.celebrate` | Correct streak, stage clear, collection unlock | Both arms raised; one foot may lift; face remains readable |
| `art.moa.encourage` | Retry after an incorrect answer | One hand to chest and one open hand; no sad or scolding gesture |
| `art.moa.point` | Optional tutorial and route guidance | Open palm points away from the body; never covers the face |

## Rendering and placement

- Keep the face and gesture readable at a 360px-wide phone preview.
- Place Moa on transparent backgrounds and preserve fully transparent corners. Do not add baked speech bubbles, UI, cast-shadow rectangles, or text.
- Use the neutral pose by default. Spoken help is replayable from the speaker button and skippable; pose changes must not block answering.
- Do not mirror a pose if doing so changes satchel continuity. Use a layout-side change before a character flip.

## Source and master policy

The approved opaque `moa-anchor-v1.png` is the visual identity reference only. Each pose has its own exact saved generation prompt and immutable 1254×1254 source candidate: `moa-neutral-v1`, `moa-celebrate-v1`, `moa-encourage-v1`, and `moa-point-v1`. Those non-release candidates are the genuine masters recorded in `assets/asset-manifest.json`; the transparent 1024×1024 runtime PNGs are reviewed derivatives. Krita was not available during production, so no `.kra` file is claimed or fabricated. Future editable masters may be added only when created by a real authoring tool and registered with their own hashes.
