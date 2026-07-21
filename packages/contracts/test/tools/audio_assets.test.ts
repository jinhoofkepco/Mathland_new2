import path from "node:path";

import { describe, expect, it } from "vitest";

import { validateAudioWorkspace } from "../../../../tools/assets/validate_audio.js";

const ROOT = path.resolve(new URL("../../../..", import.meta.url).pathname);

const MUSIC_IDS = ["exploration_loop", "concentration_loop", "boss_loop"];
const SFX_IDS = [
  "button_down", "button_release", "correct", "wrong", "heart_loss", "combo_1",
  "combo_2", "combo_3", "boss", "level_up", "reward", "manipulative_place",
];
const VOICE_IDS = [
  "moa_home_welcome", "moa_tutorial_counting", "moa_tutorial_number_bonds",
  "moa_tutorial_ten_frame", "moa_tutorial_base_ten", "moa_tutorial_number_line",
  "moa_tutorial_basic_operations", "moa_reward", "moa_level_up",
];

describe("offline release audio", () => {
  it("contains the exact stable music, SFX, and Korean dialogue IDs", async () => {
    const report = await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: false,
    });
    expect(report.ids.music).toEqual(MUSIC_IDS);
    expect(report.ids.sfx).toEqual(SFX_IDS);
    expect(report.ids.voice).toEqual(VOICE_IDS);
    expect(report.issues).toEqual([]);
  });

  it("passes sample-rate, channel, duration, loudness, peak, and loop seam gates", async () => {
    const report = await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: true,
    });
    expect(report.issues).toEqual([]);
    expect(report.filesChecked).toBe(24);
  }, 60_000);

  it("never lets automatic voice narration block a question", async () => {
    const report = await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: false,
    });
    expect(report.manifest.questionNarration.autoplay).toBe(false);
    expect(report.manifest.questionNarration.trigger).toBe("speaker_control_only");
    expect(report.manifest.questionNarration.blocksInput).toBe(false);
    expect(report.manifest.voice.every((entry) => entry.skippable && entry.replayable)).toBe(true);
  });
});
