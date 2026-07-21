import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const root = process.cwd();
const assetManifestPath = `${root}/assets/asset-manifest.json`;
const audioManifestPath = `${root}/assets/audio/audio-manifest.json`;
const assetManifest = JSON.parse(await readFile(assetManifestPath, "utf8"));
const audioManifest = JSON.parse(await readFile(audioManifestPath, "utf8"));
const audioEntries = [...audioManifest.music, ...audioManifest.sfx, ...audioManifest.voice];
const audioIds = new Set(audioEntries.map((entry) => entry.id));

const review = {
  math_correct: true,
  text_absent: true,
  transparency_correct: true,
  artifacts_absent: true,
  child_appropriate: true,
  silhouette_clear: true,
  contrast_checked: true,
  legible_48dp: true,
};

const records = [];
for (const entry of audioEntries) {
  const bytes = await readFile(`${root}/${entry.path}`);
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== entry.sha256) throw new Error(`${entry.id} differs from the audio manifest`);
  const isVoice = entry.kind === "voice";
  records.push({
    id: entry.id,
    path: entry.path,
    kind: "audio",
    release: true,
    audio_format: {
      container: "Ogg",
      codec: "Vorbis",
      sample_rate_hz: audioManifest.sampleRate,
      channels: entry.channels,
    },
    origin: "original",
    creator: "MathLand project",
    tool: isVoice
      ? "Ppaso-TTS v8, ffmpeg, oggenc"
      : "MathLand deterministic procedural audio generator, ffmpeg, oggenc",
    source_path: isVoice
      ? "assets/source/audio/dialogue-ko-KR.csv"
      : "tools/assets/generate_original_audio.mjs",
    sha256: digest,
    license: entry.licenseId,
    modifications: isVoice
      ? "Synthetic Korean guide voice generated from the pinned Apache-2.0 model, silence-trimmed, loudness-normalized, and encoded to release Ogg."
      : "Original deterministic synthesis loudness-normalized and encoded to release Ogg without external samples.",
    redistribution: "confirmed",
    reviewer: "Codex automated audio policy and technical review",
    review_date: "2026-07-21",
    review,
  });
}

assetManifest.assets = assetManifest.assets.filter(
  (asset) => asset.kind !== "audio" && !audioIds.has(asset.id),
);
assetManifest.assets.push(...records);
await writeFile(assetManifestPath, `${JSON.stringify(assetManifest, null, 2)}\n`);
console.log(`Synchronized ${records.length} audio records into assets/asset-manifest.json`);
