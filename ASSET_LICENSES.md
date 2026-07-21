# MathLand Asset Licenses

All records below are covered by project-specific provenance and redistribution review. The generated raster work is original user-directed generated work made with `OpenAI built-in image_gen`; redistribution is confirmed by the project owner. The project-native SVGs are original MathLand work. No legacy SeoaQuiz raster art and no third-party asset is included.

Production masters are the checked-in PNG release files recorded by `master_path`. No Krita authoring tool was available, so the repository intentionally contains no fabricated `.kra` file. The saved prompts and generated source candidates provide the reproducible provenance chain.

- `app.mathland_launcher` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/app/mathland_launcher.svg
- `ui.activity.addition_ones` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/addition_ones.svg
- `ui.activity.subtraction_ones` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/subtraction_ones.svg
- `ui.activity.multiplication` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/multiplication.svg
- `ui.activity.common_multiples_lcm` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/common_multiples_lcm.svg
- `ui.activity.prime_factorization` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/prime_factorization.svg
- `ui.activity.foundations_counting` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_counting.svg
- `ui.activity.foundations_number_bonds` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_number_bonds.svg
- `ui.activity.foundations_ten_frame` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_ten_frame.svg
- `ui.activity.foundations_base_ten` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_base_ten.svg
- `ui.activity.foundations_number_line` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_number_line.svg
- `ui.activity.foundations_basic_operations` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/activities/foundations_basic_operations.svg
- `ui.status.correct` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/status/correct.svg
- `ui.status.wrong` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/status/wrong.svg
- `ui.status.heart` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/status/heart.svg
- `ui.status.speaker` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/icons/status/speaker.svg
- `ui.learning.ten_frame` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/learning/ten_frame.svg
- `ui.learning.ten_rod` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/learning/ten_rod.svg
- `ui.learning.unit_cube` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/learning/unit_cube.svg
- `ui.learning.number_line_marker` — `MathLand-Original-1.0`; original; redistribution confirmed; assets/ui/learning/number_line_marker.svg
- `source.generated.moa_anchor_v1` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/source/art/generated/moa-anchor-v1.png
- `source.generated.exploration_island_v1` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/source/art/generated/exploration-island-v1.png
- `source.generated.collection_shells_keyed_v1` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/source/art/generated/collection-shells-keyed-v1.png
- `art.moa.neutral` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/moa/moa_neutral.png
- `art.moa.celebrate` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/moa/moa_celebrate.png
- `art.moa.encourage` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/moa/moa_encourage.png
- `art.moa.point` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/moa/moa_point.png
- `art.island.exploration_bg` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/island/exploration_island_bg.png
- `art.collection.shells` — `MathLand-Generated-Original-1.0`; generated-derived; redistribution confirmed; assets/art/collection/collection_shells.png

## Original MathLand audio

The machine-readable rights ledger is the ordered set of `kind: "audio"` records in `assets/asset-manifest.json`. Audio validation joins every release ID, path, SHA-256, channel count, license, redistribution assertion, review assertion, and kind-specific provenance against that structured record; the human-readable lists below are documentation rather than admission by token matching.

`MathLand-Original-Audio-1.0` covers the deterministic procedural music and sound effects authored specifically for MathLand in `tools/assets/generate_original_audio.mjs`. Redistribution is confirmed. No third-party sample, system voice, or recorded performer is used.

- `exploration_loop`, `concentration_loop`, `boss_loop`
- `button_down`, `button_release`, `correct`, `wrong`, `heart_loss`, `combo_1`, `combo_2`, `combo_3`, `boss`, `level_up`, `reward`, `manipulative_place`

## Ppaso synthetic Korean guide voice

`Ppaso-TTS-v8-Apache-2.0` covers the nine synthetic-derived guide clips generated from the Apache-2.0 Ppaso-TTS v8 model. Source: https://huggingface.co/akamotaco/ppaso-tts-v1 at exact revision `53d09664c4f636a5fb6f2ebe3ec22cd83ee249b9`. The reviewed model card identifies a Korean single female synthetic voice, synthetic training speech produced with Apache-2.0 CosyVoice, no real-person identity, and no voice cloning. The model weights are not redistributed; only MathLand's generated Ogg outputs are included. Redistribution of the outputs is confirmed by the project owner. Exact Korean inputs are in `assets/source/audio/dialogue-ko-KR.csv`; generation and post-processing are recorded in `tools/assets/generate_ppaso_voice.py` and `assets/source/audio/AUDIO_DELIVERY_SPEC.md`.

- `moa_home_welcome`, `moa_tutorial_counting`, `moa_tutorial_number_bonds`, `moa_tutorial_ten_frame`, `moa_tutorial_base_ten`, `moa_tutorial_number_line`, `moa_tutorial_basic_operations`, `moa_reward`, `moa_level_up`
