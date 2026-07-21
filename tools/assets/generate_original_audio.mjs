import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const SAMPLE_RATE = 48_000;
const TAU = Math.PI * 2;

function midi(note) {
  return 440 * 2 ** ((note - 69) / 12);
}

function envelope(time, duration, attack = 0.02, release = 0.12) {
  return Math.min(1, time / Math.max(attack, 1 / SAMPLE_RATE), (duration - time) / Math.max(release, 1 / SAMPLE_RATE));
}

function addTone(channels, start, duration, frequency, amplitude, options = {}) {
  const begin = Math.max(0, Math.floor(start * SAMPLE_RATE));
  const end = Math.min(channels[0].length, Math.ceil((start + duration) * SAMPLE_RATE));
  const pan = options.pan ?? 0;
  const leftGain = channels.length === 1 ? 1 : Math.sqrt((1 - pan) / 2);
  const rightGain = channels.length === 1 ? 0 : Math.sqrt((1 + pan) / 2);
  const harmonics = options.harmonics ?? [[1, 1], [2, 0.15], [3, 0.05]];
  const attack = options.attack ?? 0.02;
  const release = options.release ?? 0.12;
  const endFrequency = options.endFrequency ?? frequency;
  const vibrato = options.vibrato ?? 0;
  for (let index = begin; index < end; index += 1) {
    const local = index / SAMPLE_RATE - start;
    const progress = local / duration;
    const hz = frequency + (endFrequency - frequency) * progress + Math.sin(TAU * 5.2 * local) * vibrato;
    const phase = TAU * hz * local;
    let wave = 0;
    for (const [multiple, weight] of harmonics) wave += Math.sin(phase * multiple) * weight;
    const value = wave * amplitude * Math.max(0, envelope(local, duration, attack, release));
    channels[0][index] += value * leftGain;
    if (channels.length === 2) channels[1][index] += value * rightGain;
  }
}

function addBell(channels, start, duration, note, amplitude, pan = 0) {
  addTone(channels, start, duration, midi(note), amplitude, {
    pan,
    attack: 0.008,
    release: Math.min(0.65, duration * 0.65),
    harmonics: [[1, 1], [2, 0.42], [3, 0.16], [4.02, 0.09]],
  });
}

function addPad(channels, start, duration, notes, amplitude) {
  notes.forEach((note, index) => addTone(channels, start, duration, midi(note), amplitude, {
    pan: (index - (notes.length - 1) / 2) * 0.35,
    attack: 0.22,
    release: 0.45,
    vibrato: 0.35,
    harmonics: [[1, 1], [2, 0.09], [0.5, 0.05]],
  }));
}

function noiseGenerator(seed) {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return ((state >>> 0) / 0xffffffff) * 2 - 1;
  };
}

function addNoise(channels, start, duration, amplitude, seed, options = {}) {
  const begin = Math.max(0, Math.floor(start * SAMPLE_RATE));
  const end = Math.min(channels[0].length, Math.ceil((start + duration) * SAMPLE_RATE));
  const random = noiseGenerator(seed);
  let filtered = 0;
  const pan = options.pan ?? 0;
  const leftGain = channels.length === 1 ? 1 : Math.sqrt((1 - pan) / 2);
  const rightGain = channels.length === 1 ? 0 : Math.sqrt((1 + pan) / 2);
  for (let index = begin; index < end; index += 1) {
    const local = index / SAMPLE_RATE - start;
    filtered = filtered * (options.smooth ?? 0.25) + random() * (1 - (options.smooth ?? 0.25));
    const value = filtered * amplitude * Math.max(0, envelope(local, duration, options.attack ?? 0.002, options.release ?? 0.04));
    channels[0][index] += value * leftGain;
    if (channels.length === 2) channels[1][index] += value * rightGain;
  }
}

function addKick(channels, start, amplitude = 0.18) {
  addTone(channels, start, 0.28, 105, amplitude, { attack: 0.002, release: 0.22, endFrequency: 44, harmonics: [[1, 1], [2, 0.12]] });
}

function circularEcho(channels, delaySeconds, gain) {
  const delay = Math.round(delaySeconds * SAMPLE_RATE);
  for (const channel of channels) {
    const source = channel.slice();
    for (let index = 0; index < channel.length; index += 1) {
      channel[index] += source[(index - delay + channel.length) % channel.length] * gain;
    }
  }
}

function createBuffer(duration, channelCount) {
  return Array.from({ length: channelCount }, () => new Float64Array(Math.round(duration * SAMPLE_RATE)));
}

function explorationLoop() {
  const channels = createBuffer(12, 2);
  const chords = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]];
  chords.forEach((chord, index) => addPad(channels, index * 3 + 0.04, 2.88, chord, 0.055));
  const melody = [72, 74, 76, 79, 76, 74, 72, 69, 72, 74, 77, 76, 74, 71, 69, 67];
  melody.forEach((note, index) => addBell(channels, 0.12 + index * 0.72, 0.55, note, 0.095, index % 2 ? 0.3 : -0.3));
  for (let beat = 0; beat < 20; beat += 1) {
    const chord = chords[Math.floor(beat / 5)];
    addTone(channels, 0.08 + beat * 0.6, 0.42, midi(chord[0] - 12), 0.07, { attack: 0.01, release: 0.22, harmonics: [[1, 1], [2, 0.12]], pan: -0.08 });
    if (beat % 2 === 1) addNoise(channels, 0.08 + beat * 0.6, 0.08, 0.018, 100 + beat, { smooth: 0.72, pan: 0.35 });
  }
  circularEcho(channels, 0.24, 0.16);
  circularEcho(channels, 0.48, 0.08);
  return channels;
}

function concentrationLoop() {
  const channels = createBuffer(16, 2);
  const chords = [[62, 66, 69], [59, 62, 66], [55, 59, 62], [57, 61, 64]];
  chords.forEach((chord, index) => addPad(channels, index * 4 + 0.04, 3.88, chord, 0.047));
  const melody = [74, 78, 81, 78, 71, 74, 78, 76];
  melody.forEach((note, index) => addBell(channels, 0.16 + index * 1.95, 1.25, note, 0.065, index % 2 ? 0.22 : -0.22));
  for (let beat = 0; beat < 24; beat += 1) {
    const chord = chords[Math.floor(beat / 6)];
    addTone(channels, 0.1 + beat * (2 / 3), 0.5, midi(chord[0] - 12), 0.045, { attack: 0.025, release: 0.28, harmonics: [[1, 1], [2, 0.06]], pan: -0.12 });
  }
  circularEcho(channels, 0.36, 0.18);
  circularEcho(channels, 0.72, 0.09);
  return channels;
}

function bossLoop() {
  const channels = createBuffer(12, 2);
  const chords = [[50, 53, 57], [48, 52, 55], [46, 50, 53], [48, 52, 55]];
  chords.forEach((chord, index) => addPad(channels, index * 3 + 0.03, 2.9, chord, 0.055));
  const arp = [62, 65, 69, 65, 60, 64, 67, 64, 58, 62, 65, 62, 60, 64, 67, 71];
  for (let step = 0; step < 32; step += 1) {
    addBell(channels, 0.06 + step * 0.36, 0.3, arp[step % arp.length], 0.065, step % 2 ? 0.4 : -0.4);
  }
  for (let beat = 0; beat < 24; beat += 1) {
    const at = 0.05 + beat * 0.5;
    addKick(channels, at, beat % 4 === 0 ? 0.2 : 0.13);
    if (beat % 2 === 1) addNoise(channels, at, 0.11, 0.035, 500 + beat, { smooth: 0.5, pan: beat % 4 === 1 ? -0.2 : 0.2 });
  }
  circularEcho(channels, 0.18, 0.12);
  return channels;
}

function createSfx(id) {
  const durations = {
    button_down: 0.09, button_release: 0.11, correct: 0.55, wrong: 0.42,
    heart_loss: 0.72, combo_1: 0.62, combo_2: 0.78, combo_3: 1.02,
    boss: 1.28, level_up: 2.45, reward: 1.75, manipulative_place: 0.14,
  };
  const channels = createBuffer(durations[id], 1);
  if (id === "button_down") {
    addTone(channels, 0.002, 0.075, 390, 0.25, { endFrequency: 270, attack: 0.001, release: 0.055, harmonics: [[1, 1], [2, 0.24]] });
    addNoise(channels, 0, 0.035, 0.08, 1, { smooth: 0.5 });
  } else if (id === "button_release") {
    addTone(channels, 0.004, 0.09, 330, 0.2, { endFrequency: 510, attack: 0.002, release: 0.06, harmonics: [[1, 1], [2, 0.18]] });
  } else if (id === "correct") {
    [72, 76, 79].forEach((note, index) => addBell(channels, 0.02 + index * 0.11, 0.28, note, 0.16));
    addNoise(channels, 0.27, 0.16, 0.025, 2, { smooth: 0.82 });
  } else if (id === "wrong") {
    addTone(channels, 0.015, 0.31, 300, 0.17, { endFrequency: 205, attack: 0.008, release: 0.18, harmonics: [[1, 1], [1.5, 0.15], [2, 0.09]] });
  } else if (id === "heart_loss") {
    addKick(channels, 0.01, 0.3);
    addTone(channels, 0.06, 0.55, 245, 0.16, { endFrequency: 105, attack: 0.01, release: 0.28, harmonics: [[1, 1], [2, 0.12]] });
  } else if (id.startsWith("combo_")) {
    const tier = Number(id.at(-1));
    const notes = [72, 76, 79, 84, 88].slice(0, tier + 2);
    notes.forEach((note, index) => addBell(channels, 0.015 + index * 0.105, 0.34 + tier * 0.06, note, 0.13 + tier * 0.015));
    addNoise(channels, 0.22, 0.2 + tier * 0.08, 0.022, 20 + tier, { smooth: 0.86 });
  } else if (id === "boss") {
    addKick(channels, 0.01, 0.3);
    addKick(channels, 0.34, 0.24);
    addTone(channels, 0.04, 1.05, 115, 0.14, { endFrequency: 520, attack: 0.02, release: 0.2, harmonics: [[1, 1], [2, 0.2], [3, 0.07]] });
  } else if (id === "level_up") {
    [60, 64, 67, 72, 76, 79, 84].forEach((note, index) => addBell(channels, 0.03 + index * 0.19, 0.75, note, 0.12));
    [72, 76, 79].forEach((note) => addTone(channels, 1.35, 0.95, midi(note), 0.07, { attack: 0.04, release: 0.5 }));
  } else if (id === "reward") {
    [84, 88, 91, 96].forEach((note, index) => addBell(channels, 0.03 + index * 0.12, 0.62, note, 0.13));
    addNoise(channels, 0.35, 0.9, 0.025, 77, { smooth: 0.9 });
  } else if (id === "manipulative_place") {
    addTone(channels, 0.001, 0.12, 440, 0.22, { endFrequency: 610, attack: 0.001, release: 0.08, harmonics: [[1, 1], [2, 0.16]] });
  }
  return channels;
}

function encodeWav(channels) {
  let peak = 0;
  for (const channel of channels) for (const sample of channel) peak = Math.max(peak, Math.abs(sample));
  const scale = peak > 0.82 ? 0.82 / peak : 1;
  const frameCount = channels[0].length;
  const dataLength = frameCount * channels.length * 2;
  const output = Buffer.alloc(44 + dataLength);
  output.write("RIFF", 0); output.writeUInt32LE(36 + dataLength, 4); output.write("WAVE", 8);
  output.write("fmt ", 12); output.writeUInt32LE(16, 16); output.writeUInt16LE(1, 20);
  output.writeUInt16LE(channels.length, 22); output.writeUInt32LE(SAMPLE_RATE, 24);
  output.writeUInt32LE(SAMPLE_RATE * channels.length * 2, 28); output.writeUInt16LE(channels.length * 2, 32);
  output.writeUInt16LE(16, 34); output.write("data", 36); output.writeUInt32LE(dataLength, 40);
  let offset = 44;
  for (let frame = 0; frame < frameCount; frame += 1) {
    for (const channel of channels) {
      output.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(channel[frame] * scale * 32767))), offset);
      offset += 2;
    }
  }
  return output;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: options.binary ? null : "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} failed: ${String(result.stderr)}`);
  return result;
}

function loudnessAndPeak(file) {
  const loudness = run("ffmpeg", ["-hide_banner", "-nostats", "-i", file, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"]);
  const loudnessMatches = [...loudness.stderr.matchAll(/I:\s+(-?[0-9.]+) LUFS/gu)];
  const peakMatches = [...loudness.stderr.matchAll(/Peak:\s+(-?[0-9.]+) dBFS/gu)];
  if (!loudnessMatches.length || !peakMatches.length) throw new Error(`Could not measure ${file}`);
  return { lufs: Number(loudnessMatches.at(-1)[1]), peak: Number(peakMatches.at(-1)[1]) };
}

async function renderEntry(root, temp, entry, channels) {
  const wav = path.join(temp, `${entry.id}.wav`);
  const normalized = path.join(temp, `${entry.id}.normalized.wav`);
  await writeFile(wav, encodeWav(channels));
  const measured = loudnessAndPeak(wav);
  const target = entry.targetLufs;
  const gain = Math.min(target - measured.lufs, -1.2 - measured.peak);
  const output = path.join(root, entry.path);
  await mkdir(path.dirname(output), { recursive: true });
  run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-i", wav, "-af", `volume=${gain.toFixed(4)}dB`, "-ar", String(SAMPLE_RATE), "-ac", String(channels.length), "-c:a", "pcm_s16le", normalized]);
  const args = ["-Q", "-q", "5", "-s", String(entry.serial), "-t", entry.id];
  if (entry.kind === "music") args.push("-c", "LOOPSTART=0", "-c", `LOOPEND=${channels[0].length}`);
  args.push("-o", output, normalized);
  run("oggenc", args);
  const bytes = await readFile(output);
  entry.sha256 = createHash("sha256").update(bytes).digest("hex");
}

async function main() {
  const root = process.cwd();
  const manifestPath = path.join(root, "assets/audio/audio-manifest.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const temp = await mkdtemp(path.join(tmpdir(), "mathland-audio-"));
  try {
    const loops = { exploration_loop: explorationLoop, concentration_loop: concentrationLoop, boss_loop: bossLoop };
    for (const entry of manifest.music) await renderEntry(root, temp, entry, loops[entry.id]());
    for (const entry of manifest.sfx) await renderEntry(root, temp, entry, createSfx(entry.id));
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

await main();
