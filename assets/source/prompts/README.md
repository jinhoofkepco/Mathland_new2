# Saved Image-Generation Prompts

These files are the exact final prompts used through the OpenAI built-in `image_gen` workflow on 2026-07-21. The generated candidates are immutable provenance inputs, not runtime assets.

| Prompt | Candidate | Release derivatives |
| --- | --- | --- |
| `moa-anchor-v1.md` | `../art/generated/moa-anchor-v1.png` | four transparent Moa pose PNG masters |
| `exploration-island-v1.md` | `../art/generated/exploration-island-v1.png` | portrait exploration island background |
| `collection-shells-v1.md` | `../art/generated/collection-shells-keyed-v1.png` | transparent 2048×2048 4×3 collection sheet |

Every prompt and candidate SHA-256 is pinned in `assets/asset-manifest.json`. Candidate records use `release: false`; only reviewed derivatives with confirmed redistribution rights may use `release: true`. Do not replace a saved prompt or candidate in place. A new generation requires a new versioned prompt, candidate ID, source hash, review record, and release hash.

The workflow did not use a CLI image-generation fallback. No source candidate may be referenced from a Godot scene, resource, script, or content package.
