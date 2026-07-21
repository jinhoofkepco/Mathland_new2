import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
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

type MutableManifest = Record<string, unknown> & {
  music: Array<Record<string, unknown>>;
  sfx: Array<Record<string, unknown>>;
  voice: Array<Record<string, unknown>>;
  voiceModel: Record<string, unknown>;
};

type MutableAssetManifest = Record<string, unknown> & {
  assets: Array<Record<string, unknown>>;
};

async function validateMutation(
  mutate: (manifest: MutableManifest) => void,
  technical = false,
) {
  const directory = await mkdtemp(path.join(tmpdir(), "mathland-audio-manifest-"));
  const manifestPath = path.join(directory, "audio-manifest.json");
  try {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/audio/audio-manifest.json"), "utf8"),
    ) as MutableManifest;
    mutate(manifest);
    await writeFile(manifestPath, `${JSON.stringify(manifest)}\n`, "utf8");
    return await validateAudioWorkspace({
      root: ROOT,
      manifestPath,
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical,
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function validateRightsMutation(
  mutate: (manifest: MutableAssetManifest) => void,
) {
  const directory = await mkdtemp(path.join(tmpdir(), "mathland-audio-rights-"));
  const assetManifestPath = path.join(directory, "asset-manifest.json");
  try {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as MutableAssetManifest;
    mutate(manifest);
    await writeFile(assetManifestPath, `${JSON.stringify(manifest)}\n`, "utf8");
    return await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      assetManifestPath,
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: true,
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

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

  it("keeps activity instruction replay speaker-only and non-blocking", async () => {
    const report = await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: false,
    });
    expect(report.manifest.instructionVoice.trigger).toBe("speaker_control_only");
    expect(report.manifest.instructionVoice.contentScope).toBe("activity_tutorial");
    expect(report.manifest.instructionVoice.blocksInput).toBe(false);
    expect(report.manifest.voice.every((entry) => entry.skippable && entry.replayable)).toBe(true);
    expect(Object.values(report.manifest.instructionVoice.activityDialogueMap)).toEqual(
      expect.arrayContaining(VOICE_IDS.slice(1, 7)),
    );
  });

  it.each([
    ["every-question autoplay", (manifest: MutableManifest) => { manifest.voice[0]!.autoplay = "every_question"; }],
    ["missing autoplay", (manifest: MutableManifest) => { delete manifest.voice[0]!.autoplay; }],
    ["missing skippable", (manifest: MutableManifest) => { delete manifest.voice[0]!.skippable; }],
    ["missing replayable", (manifest: MutableManifest) => { delete manifest.voice[0]!.replayable; }],
    ["blank license", (manifest: MutableManifest) => { manifest.sfx[0]!.licenseId = ""; }],
    ["disabled music loop", (manifest: MutableManifest) => { manifest.music[0]!.loop = false; }],
    ["missing SFX duration", (manifest: MutableManifest) => { delete manifest.sfx[0]!.maxDurationSeconds; }],
    ["missing voice duration", (manifest: MutableManifest) => { delete manifest.voice[0]!.maxDurationSeconds; }],
    ["missing Ogg serial", (manifest: MutableManifest) => { delete manifest.sfx[0]!.serial; }],
    ["unknown manifest field", (manifest: MutableManifest) => { manifest.voice[0]!.unreviewed = true; }],
    ["non-object audio entry", (manifest: MutableManifest) => { manifest.sfx[0] = null as unknown as Record<string, unknown>; }],
  ])("rejects the %s mutation", async (_label, mutate) => {
    const report = await validateMutation(mutate);
    expect(report.issues.map((issue) => issue.code)).toContain("MANIFEST_SCHEMA_INVALID");
  });

  it.each([
    ["exploration music reassigned to boss autoplay", (manifest: MutableManifest) => {
      manifest.music[0]!.autoplay = "boss_context";
    }],
    ["ordinary button effect granted the four-second cinematic budget", (manifest: MutableManifest) => {
      manifest.sfx[0]!.maxDurationSeconds = 4;
    }],
    ["voice peak ceiling relaxed to -0.5 dBFS", (manifest: MutableManifest) => {
      manifest.voice[0]!.maxPeakDbfs = -0.5;
    }],
    ["music peak ceiling relaxed to -0.5 dBFS", (manifest: MutableManifest) => {
      manifest.music[0]!.maxPeakDbfs = -0.5;
    }],
    ["short-effect RMS tolerance widened to 2 dB", (manifest: MutableManifest) => {
      manifest.sfx[0]!.rmsToleranceDb = 2;
    }],
    ["short-effect RMS target rewritten dishonestly", (manifest: MutableManifest) => {
      manifest.sfx[0]!.targetRmsDbfs = Number(manifest.sfx[0]!.targetRmsDbfs) + 1.5;
    }],
  ])("rejects the reviewed-policy adversary: %s, including in technical mode", async (_label, mutate) => {
    const report = await validateMutation(mutate, true);
    expect(report.issues.map((item) => item.code)).toContain("ENTRY_POLICY_INVALID");
  }, 60_000);

  it.each([
    ["voice license swapped while the human document still contains both license tokens", (manifest: MutableAssetManifest) => {
      const record = manifest.assets.find((item) => item.id === "moa_home_welcome")!;
      record.license = "MathLand-Original-Audio-1.0";
    }],
    ["rights review assertion removed from one exact asset record", (manifest: MutableAssetManifest) => {
      const record = manifest.assets.find((item) => item.id === "button_down")!;
      (record.review as Record<string, unknown>).rights_checked = false;
    }],
  ])("rejects the structured-rights adversary: %s", async (_label, mutate) => {
    const report = await validateRightsMutation(mutate);
    expect(report.issues.map((item) => item.code)).toContain("RIGHTS_LEDGER_MISMATCH");
  }, 60_000);

  it("cross-checks every voice delivery policy against the dialogue CSV", async () => {
    const report = await validateMutation((manifest) => {
      manifest.voice[1]!.maxDurationSeconds = 99;
    });
    expect(report.issues.map((issue) => issue.code)).toContain("DIALOGUE_POLICY_MISMATCH");
  });

  it("verifies the manifest serial against the actual Ogg bitstream", async () => {
    const report = await validateMutation((manifest) => {
      manifest.sfx[0]!.serial = 4_294_967_000;
    });
    expect(report.issues.map((issue) => issue.code)).toContain("OGG_SERIAL_MISMATCH");
  });

  it("verifies pinned synthetic-model metadata against the actual voice comments", async () => {
    const report = await validateMutation((manifest) => {
      manifest.voiceModel.revision = "0".repeat(40);
    }, true);
    expect(report.issues.map((issue) => issue.code)).toContain("VOICE_MODEL_METADATA_INVALID");
  }, 60_000);

  it("uses measured short-effect RMS targets instead of misleading integrated-LUFS claims", async () => {
    const report = await validateAudioWorkspace({
      root: ROOT,
      manifestPath: path.join(ROOT, "assets/audio/audio-manifest.json"),
      licensesPath: path.join(ROOT, "ASSET_LICENSES.md"),
      technical: true,
    });
    expect(report.manifest.sfx.every((entry) => entry.targetLufs === undefined)).toBe(true);
    expect(report.manifest.sfx.every((entry) => typeof entry.targetRmsDbfs === "number")).toBe(true);
    expect(report.issues).toEqual([]);
  }, 60_000);

  it("keeps kind-specific central provenance for original synthesis and synthetic voice", async () => {
    const central = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: Array<Record<string, unknown>> };
    const audio = central.assets.filter((record) => record.kind === "audio");
    expect(audio).toHaveLength(24);
    for (const record of audio) {
      expect(Object.keys(record.review as Record<string, unknown>).sort()).toEqual([
        "child_appropriate",
        "clipping_absent",
        "content_checked",
        "release_playback_checked",
        "rights_checked",
        "technical_checked",
      ]);
      if (VOICE_IDS.includes(String(record.id))) {
        expect(record.origin).toBe("synthetic-derived");
        expect(record.creator).toBe("MathLand synthetic guide voice");
        expect(record.generation_script).toBe("tools/assets/generate_ppaso_voice.py");
        expect(record.input_path).toBe("assets/source/audio/dialogue-ko-KR.csv");
        expect(record.external_model).toEqual({
          url: "https://huggingface.co/akamotaco/ppaso-tts-v1",
          revision: "53d09664c4f636a5fb6f2ebe3ec22cd83ee249b9",
          license: "Apache-2.0",
        });
      } else {
        expect(record.origin).toBe("original");
        expect(record.source_path).toBe("tools/assets/generate_original_audio.mjs");
        expect(record).not.toHaveProperty("external_model");
      }
    }
  });
});
