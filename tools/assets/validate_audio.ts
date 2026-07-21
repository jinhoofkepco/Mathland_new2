import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { z } from "zod";

const MUSIC_IDS = ["exploration_loop", "concentration_loop", "boss_loop"] as const;
const SFX_IDS = [
  "button_down", "button_release", "correct", "wrong", "heart_loss", "combo_1",
  "combo_2", "combo_3", "boss", "level_up", "reward", "manipulative_place",
] as const;
const VOICE_IDS = [
  "moa_home_welcome", "moa_tutorial_counting", "moa_tutorial_number_bonds",
  "moa_tutorial_ten_frame", "moa_tutorial_base_ten", "moa_tutorial_number_line",
  "moa_tutorial_basic_operations", "moa_reward", "moa_level_up",
] as const;
const VOICE_MODEL_URL = "https://huggingface.co/akamotaco/ppaso-tts-v1";
const VOICE_MODEL_REVISION = "53d09664c4f636a5fb6f2ebe3ec22cd83ee249b9";
const ORIGINAL_LICENSE = "MathLand-Original-Audio-1.0";
const VOICE_LICENSE = "Ppaso-TTS-v8-Apache-2.0";
const VOICE_POLICY_BY_ID: Readonly<Record<(typeof VOICE_IDS)[number], string>> = {
  moa_home_welcome: "first_home",
  moa_tutorial_counting: "first_activity_entry",
  moa_tutorial_number_bonds: "first_activity_entry",
  moa_tutorial_ten_frame: "first_activity_entry",
  moa_tutorial_base_ten: "first_activity_entry",
  moa_tutorial_number_line: "first_activity_entry",
  moa_tutorial_basic_operations: "first_activity_entry",
  moa_reward: "reward_event",
  moa_level_up: "level_up_event",
};
const ACTIVITY_DIALOGUE_MAP = {
  foundation_ten_rods: "moa_tutorial_base_ten",
  foundations_counting: "moa_tutorial_counting",
  foundations_number_bonds: "moa_tutorial_number_bonds",
  foundations_ten_frame: "moa_tutorial_ten_frame",
  foundations_base_ten: "moa_tutorial_base_ten",
  foundations_number_line: "moa_tutorial_number_line",
  foundations_basic_operations: "moa_tutorial_basic_operations",
} as const;

type AudioKind = "music" | "sfx" | "voice";

const SafeId = z.string().regex(/^[a-z][a-z0-9_]{2,63}$/u);
const ReleasePath = z.string().regex(/^assets\/audio\/[a-zA-Z0-9_./-]+\.ogg$/u);
const Sha256 = z.string().regex(/^[a-f0-9]{64}$/u);
const Serial = z.number().int().min(1).max(0xffff_ffff);
const CommonEntryFields = {
  id: SafeId,
  path: ReleasePath,
  channels: z.number().int(),
  maxDurationSeconds: z.number().positive().max(60),
  maxPeakDbfs: z.number().finite().min(-20).max(-0.5),
  licenseId: z.string().trim().min(1).max(96),
  redistribution: z.literal("confirmed"),
  serial: Serial,
  sha256: Sha256,
};

const MusicEntrySchema = z.object({
  ...CommonEntryFields,
  id: z.enum(MUSIC_IDS),
  kind: z.literal("music"),
  bus: z.literal("Music"),
  channels: z.literal(2),
  loop: z.literal(true),
  loopStartSamples: z.literal(0),
  loopEndSamples: z.number().int().positive().max(60 * 48_000),
  targetLufs: z.number().finite().min(-30).max(-12),
  autoplay: z.enum(["exploration_context", "activity_context", "boss_context"]),
  licenseId: z.literal(ORIGINAL_LICENSE),
}).strict();

const SfxEntrySchema = z.object({
  ...CommonEntryFields,
  id: z.enum(SFX_IDS),
  kind: z.literal("sfx"),
  bus: z.literal("SFX"),
  channels: z.literal(1),
  maxDurationSeconds: z.number().positive().max(4),
  targetRmsDbfs: z.number().finite().min(-40).max(-3),
  rmsToleranceDb: z.number().positive().max(2),
  licenseId: z.literal(ORIGINAL_LICENSE),
}).strict();

const VoiceEntrySchema = z.object({
  ...CommonEntryFields,
  id: z.enum(VOICE_IDS),
  kind: z.literal("voice"),
  bus: z.literal("Voice"),
  channels: z.literal(1),
  locale: z.literal("ko-KR"),
  targetLufs: z.number().finite().min(-24).max(-14),
  maxDurationSeconds: z.number().positive().max(8),
  skippable: z.literal(true),
  replayable: z.literal(true),
  autoplay: z.enum(["first_home", "first_activity_entry", "reward_event", "level_up_event"]),
  licenseId: z.literal(VOICE_LICENSE),
}).strict();

const VoiceModelSchema = z.object({
  url: z.string().url(),
  revision: z.string().regex(/^[a-f0-9]{40}$/u),
  license: z.literal("Apache-2.0"),
  synthetic: z.literal(true),
  realPersonIdentity: z.literal(false),
  generationScript: z.literal("tools/assets/generate_ppaso_voice.py"),
  inputCsv: z.literal("assets/source/audio/dialogue-ko-KR.csv"),
}).strict();

const InstructionVoiceSchema = z.object({
  trigger: z.literal("speaker_control_only"),
  contentScope: z.literal("activity_tutorial"),
  blocksInput: z.literal(false),
  activityDialogueMap: z.object({
    foundation_ten_rods: z.literal("moa_tutorial_base_ten"),
    foundations_counting: z.literal("moa_tutorial_counting"),
    foundations_number_bonds: z.literal("moa_tutorial_number_bonds"),
    foundations_ten_frame: z.literal("moa_tutorial_ten_frame"),
    foundations_base_ten: z.literal("moa_tutorial_base_ten"),
    foundations_number_line: z.literal("moa_tutorial_number_line"),
    foundations_basic_operations: z.literal("moa_tutorial_basic_operations"),
  }).strict(),
}).strict();

const AudioManifestSchema = z.object({
  schemaVersion: z.literal(1),
  sampleRate: z.literal(48_000),
  instructionVoice: InstructionVoiceSchema,
  voiceModel: VoiceModelSchema,
  music: z.array(MusicEntrySchema).length(MUSIC_IDS.length),
  sfx: z.array(SfxEntrySchema).length(SFX_IDS.length),
  voice: z.array(VoiceEntrySchema).length(VOICE_IDS.length),
}).strict();

export interface AudioEntry {
  id: string;
  kind: AudioKind;
  path: string;
  bus: "Music" | "SFX" | "Voice";
  channels: number;
  maxDurationSeconds: number;
  maxPeakDbfs: number;
  targetLufs?: number;
  targetRmsDbfs?: number;
  rmsToleranceDb?: number;
  loop?: boolean;
  loopStartSamples?: number;
  loopEndSamples?: number;
  locale?: string;
  skippable?: boolean;
  replayable?: boolean;
  autoplay?: string;
  licenseId: string;
  redistribution: string;
  serial: number;
  sha256: string;
}

export interface AudioManifest {
  schemaVersion: number;
  sampleRate: number;
  instructionVoice: {
    trigger: string;
    contentScope: string;
    blocksInput: boolean;
    activityDialogueMap: Record<string, string>;
  };
  voiceModel: {
    url: string;
    revision: string;
    license: string;
    synthetic: boolean;
    realPersonIdentity: boolean;
    generationScript: string;
    inputCsv: string;
  };
  music: AudioEntry[];
  sfx: AudioEntry[];
  voice: AudioEntry[];
}

export interface AudioIssue {
  code: string;
  path: Array<string | number>;
  message: string;
}

export interface AudioValidationOptions {
  root: string;
  manifestPath: string;
  licensesPath: string;
  technical: boolean;
}

export interface AudioValidationReport {
  issues: AudioIssue[];
  filesChecked: number;
  ids: { music: string[]; sfx: string[]; voice: string[] };
  manifest: AudioManifest;
}

function issue(issues: AudioIssue[], code: string, issuePath: Array<string | number>, message: string): void {
  if (!issues.some((candidate) => candidate.code === code && JSON.stringify(candidate.path) === JSON.stringify(issuePath))) {
    issues.push({ code, path: issuePath, message });
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactStringRecord(value: Record<string, string>, expected: Record<string, string>): boolean {
  const keys = Object.keys(expected);
  return Object.keys(value).length === keys.length && keys.every((key) => value[key] === expected[key]);
}

function asManifest(value: unknown): AudioManifest {
  const raw = isRecord(value) ? value : {};
  const instruction = isRecord(raw.instructionVoice) ? raw.instructionVoice : {};
  const model = isRecord(raw.voiceModel) ? raw.voiceModel : {};
  return {
    schemaVersion: typeof raw.schemaVersion === "number" ? raw.schemaVersion : 0,
    sampleRate: typeof raw.sampleRate === "number" ? raw.sampleRate : 0,
    instructionVoice: {
      trigger: typeof instruction.trigger === "string" ? instruction.trigger : "",
      contentScope: typeof instruction.contentScope === "string" ? instruction.contentScope : "",
      blocksInput: instruction.blocksInput === true,
      activityDialogueMap: isRecord(instruction.activityDialogueMap)
        ? Object.fromEntries(Object.entries(instruction.activityDialogueMap).filter((entry): entry is [string, string] => typeof entry[1] === "string"))
        : {},
    },
    voiceModel: {
      url: typeof model.url === "string" ? model.url : "",
      revision: typeof model.revision === "string" ? model.revision : "",
      license: typeof model.license === "string" ? model.license : "",
      synthetic: model.synthetic === true,
      realPersonIdentity: model.realPersonIdentity === true,
      generationScript: typeof model.generationScript === "string" ? model.generationScript : "",
      inputCsv: typeof model.inputCsv === "string" ? model.inputCsv : "",
    },
    music: Array.isArray(raw.music) ? raw.music as AudioEntry[] : [],
    sfx: Array.isArray(raw.sfx) ? raw.sfx as AudioEntry[] : [],
    voice: Array.isArray(raw.voice) ? raw.voice as AudioEntry[] : [],
  };
}

function safePath(root: string, relative: string): string | null {
  if (!relative.startsWith("assets/audio/") || path.isAbsolute(relative) || relative.includes("\\") || relative.split("/").includes("..")) return null;
  const resolved = path.resolve(root, relative);
  return resolved.startsWith(`${path.resolve(root)}${path.sep}`) ? resolved : null;
}

function runText(command: string, args: string[]): string {
  const result = spawnSync(command, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} failed: ${result.stderr}`);
  return `${result.stdout}${result.stderr}`;
}

function runBuffer(command: string, args: string[]): Buffer {
  const result = spawnSync(command, args, { maxBuffer: 128 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(`${command} failed: ${String(result.stderr)}`);
  return result.stdout;
}

function measure(file: string): { lufs: number; peakDbfs: number } {
  const output = runText("ffmpeg", ["-hide_banner", "-nostats", "-i", file, "-filter_complex", "ebur128=peak=true", "-f", "null", "-"]);
  const integrated = [...output.matchAll(/I:\s+(-?[0-9.]+) LUFS/gu)].at(-1)?.[1];
  const peak = [...output.matchAll(/Peak:\s+(-?[0-9.]+) dBFS/gu)].at(-1)?.[1];
  if (integrated === undefined || peak === undefined) throw new Error("ffmpeg did not emit loudness summary");
  return { lufs: Number(integrated), peakDbfs: Number(peak) };
}

function decode(file: string): Buffer {
  return runBuffer("ffmpeg", ["-v", "error", "-i", file, "-f", "f32le", "-acodec", "pcm_f32le", "-"]);
}

function rmsDbfs(decoded: Buffer): number {
  const samples = decoded.byteLength / 4;
  if (samples < 1) return Number.NEGATIVE_INFINITY;
  let sumSquares = 0;
  for (let index = 0; index < samples; index += 1) {
    const sample = decoded.readFloatLE(index * 4);
    sumSquares += sample * sample;
  }
  return 20 * Math.log10(Math.max(Math.sqrt(sumSquares / samples), 1e-12));
}

function seamDbfs(decoded: Buffer, channels: number): number {
  const sampleCount = decoded.byteLength / 4;
  let maximum = 0;
  for (let channel = 0; channel < channels; channel += 1) {
    const first = decoded.readFloatLE(channel * 4);
    const last = decoded.readFloatLE((sampleCount - channels + channel) * 4);
    maximum = Math.max(maximum, Math.abs(first - last));
  }
  return 20 * Math.log10(Math.max(maximum, 1e-12));
}

function leadingSilenceSeconds(decoded: Buffer, channels: number): number {
  const frames = decoded.byteLength / 4 / channels;
  const threshold = 10 ** (-50 / 20);
  for (let frame = 0; frame < frames; frame += 1) {
    for (let channel = 0; channel < channels; channel += 1) {
      if (Math.abs(decoded.readFloatLE((frame * channels + channel) * 4)) >= threshold) return frame / 48_000;
    }
  }
  return Number.POSITIVE_INFINITY;
}

function oggSerial(bytes: Buffer): number | null {
  if (bytes.byteLength < 18 || bytes.toString("ascii", 0, 4) !== "OggS") return null;
  return bytes.readUInt32LE(14);
}

function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index]!;
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') { field += '"'; index += 1; }
      else if (character === '"') quoted = false;
      else field += character;
    } else if (character === '"') quoted = true;
    else if (character === ",") { row.push(field); field = ""; }
    else if (character === "\n") { row.push(field.replace(/\r$/u, "")); rows.push(row); row = []; field = ""; }
    else field += character;
  }
  if (quoted) throw new TypeError("Dialogue CSV has an unterminated quoted field");
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

function ledgerContains(licenses: string, id: string, licenseId: string): boolean {
  return licenseId.length > 0 && licenses.includes(`\`${id}\``) && licenses.includes(`\`${licenseId}\``);
}

async function validateEntry(
  root: string,
  entry: AudioEntry,
  kind: AudioKind,
  index: number,
  licenses: string,
  model: AudioManifest["voiceModel"],
  technical: boolean,
  issues: AudioIssue[],
): Promise<boolean> {
  const basePath: Array<string | number> = [kind, index];
  if (!isRecord(entry) || typeof entry.id !== "string") {
    issue(issues, "ENTRY_INVALID", basePath, "Audio entry must be an object with a stable ID");
    return false;
  }
  const absolute = typeof entry.path === "string" ? safePath(root, entry.path) : null;
  if (!absolute || !entry.path.endsWith(".ogg") || /audition|system.voice|say-output/iu.test(entry.path)) {
    issue(issues, "PATH_INVALID", [...basePath, "path"], `${entry.id} must use a safe release Ogg path`);
    return false;
  }
  if (entry.kind !== kind || entry.bus !== (kind === "music" ? "Music" : kind === "sfx" ? "SFX" : "Voice")) {
    issue(issues, "BUS_INVALID", basePath, `${entry.id} has the wrong kind or bus`);
  }
  if (entry.channels !== (kind === "music" ? 2 : 1)) issue(issues, "CHANNEL_CONTRACT", [...basePath, "channels"], `${entry.id} channel contract is invalid`);
  if (entry.redistribution !== "confirmed" || !ledgerContains(licenses, entry.id, entry.licenseId)) {
    issue(issues, "RIGHTS_UNCONFIRMED", basePath, `${entry.id} requires its exact confirmed ledger ID and license`);
  }
  let bytes: Buffer;
  try {
    bytes = await readFile(absolute);
  } catch {
    issue(issues, "FILE_MISSING", [...basePath, "path"], `${entry.path} does not exist`);
    return false;
  }
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== entry.sha256) issue(issues, "HASH_MISMATCH", [...basePath, "sha256"], `${entry.id} SHA-256 does not match`);
  const actualSerial = oggSerial(bytes);
  if (actualSerial === null) issue(issues, "OGG_CONTAINER_INVALID", basePath, `${entry.id} has no valid Ogg identification page`);
  else if (actualSerial !== entry.serial) issue(issues, "OGG_SERIAL_MISMATCH", [...basePath, "serial"], `${entry.id} serial ${actualSerial} differs from the manifest`);
  if (!technical) return true;
  try {
    const probeText = runText("ffprobe", ["-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:stream_tags:format=duration,format_name", "-of", "json", absolute]);
    const probe = JSON.parse(probeText) as { streams?: Array<{ codec_name?: string; sample_rate?: string; channels?: number; tags?: Record<string, string> }>; format?: { duration?: string; format_name?: string } };
    const stream = probe.streams?.[0];
    const tags = stream?.tags ?? {};
    const duration = Number(probe.format?.duration);
    if (stream?.codec_name !== "vorbis" || !probe.format?.format_name?.includes("ogg")) issue(issues, "CODEC_INVALID", basePath, `${entry.id} is not Ogg Vorbis`);
    if (Number(stream?.sample_rate) !== 48_000) issue(issues, "SAMPLE_RATE_INVALID", basePath, `${entry.id} is not 48 kHz`);
    if (stream?.channels !== entry.channels) issue(issues, "CHANNEL_INVALID", basePath, `${entry.id} decoded channel count differs`);
    if (tags.title !== entry.id) issue(issues, "OGG_TITLE_INVALID", basePath, `${entry.id} title comment differs from its stable ID`);
    if (!Number.isFinite(duration) || duration <= 0 || typeof entry.maxDurationSeconds !== "number" || duration > entry.maxDurationSeconds + 0.02) issue(issues, "DURATION_INVALID", basePath, `${entry.id} duration is outside its mandatory limit`);
    if (kind === "music") {
      if (entry.loop !== true || tags.LOOPSTART !== String(entry.loopStartSamples) || tags.LOOPEND !== String(entry.loopEndSamples)) issue(issues, "LOOP_METADATA_INVALID", basePath, `${entry.id} loop contract/comments differ from the manifest`);
      if (Math.abs(duration * 48_000 - (entry.loopEndSamples ?? 0)) > 2) issue(issues, "LOOP_DURATION_INVALID", basePath, `${entry.id} decoded duration differs from its loop end`);
    }
    if (kind === "voice") {
      const expectedModel = `${model.url}@${model.revision}`;
      if (tags.LANGUAGE !== "ko-KR" || tags.SYNTHETIC_VOICE !== "true" || tags.SOURCE_MODEL !== expectedModel || tags.LICENSE !== model.license) {
        issue(issues, "VOICE_MODEL_METADATA_INVALID", basePath, `${entry.id} does not pin the reviewed synthetic voice metadata`);
      }
    }
    const levels = measure(absolute);
    if ((kind === "music" || kind === "voice") && (typeof entry.targetLufs !== "number" || Math.abs(levels.lufs - entry.targetLufs) > 2)) issue(issues, "LOUDNESS_INVALID", basePath, `${entry.id} measured ${levels.lufs} LUFS`);
    if (typeof entry.maxPeakDbfs !== "number" || levels.peakDbfs > entry.maxPeakDbfs) issue(issues, "PEAK_INVALID", basePath, `${entry.id} true peak is ${levels.peakDbfs} dBFS`);
    const decoded = decode(absolute);
    if (kind === "sfx") {
      const measuredRms = rmsDbfs(decoded);
      if (typeof entry.targetRmsDbfs !== "number" || typeof entry.rmsToleranceDb !== "number" || Math.abs(measuredRms - entry.targetRmsDbfs) > entry.rmsToleranceDb) {
        issue(issues, "SFX_RMS_INVALID", basePath, `${entry.id} measured ${measuredRms.toFixed(2)} dBFS RMS`);
      }
    }
    if (kind === "music" && seamDbfs(decoded, entry.channels) >= -50) issue(issues, "LOOP_SEAM_INVALID", basePath, `${entry.id} loop seam exceeds -50 dBFS`);
    if (kind === "voice" && leadingSilenceSeconds(decoded, entry.channels) >= 0.15) issue(issues, "VOICE_LEADING_SILENCE", basePath, `${entry.id} leading silence is too long`);
  } catch (error) {
    issue(issues, "TECHNICAL_INSPECTION_FAILED", basePath, error instanceof Error ? error.message : `${entry.id} inspection failed`);
  }
  return true;
}

function validateDialogueRows(csv: string[][], manifest: AudioManifest, issues: AudioIssue[]): void {
  const header = csv.shift();
  const expectedHeader = "id,text,pronunciation_notes,max_duration_seconds,skippable,autoplay_policy,speaker_replay";
  if (header?.join(",") !== expectedHeader || csv.some((row) => row.length !== 7)) {
    issue(issues, "DIALOGUE_CSV_INVALID", ["voice"], "Dialogue CSV shape differs from the delivery contract");
    return;
  }
  if (JSON.stringify(csv.map((row) => row[0])) !== JSON.stringify(VOICE_IDS)) {
    issue(issues, "DIALOGUE_CSV_INVALID", ["voice"], "Dialogue CSV IDs/order differ from the voice manifest");
    return;
  }
  for (const [index, row] of csv.entries()) {
    const entry = manifest.voice[index];
    if (
      !isRecord(entry)
      || row[1]?.trim().length === 0
      || Number(row[3]) !== entry.maxDurationSeconds
      || row[4] !== String(entry.skippable)
      || row[5] !== entry.autoplay
      || row[6] !== String(entry.replayable)
    ) {
      issue(issues, "DIALOGUE_POLICY_MISMATCH", ["voice", index], `${row[0] ?? index} delivery policy differs from the manifest`);
    }
  }
}

export async function validateAudioWorkspace(options: AudioValidationOptions): Promise<AudioValidationReport> {
  const issues: AudioIssue[] = [];
  let raw: unknown = {};
  try { raw = JSON.parse(await readFile(options.manifestPath, "utf8")); }
  catch (error) { issue(issues, "MANIFEST_READ_FAILED", [], error instanceof Error ? error.message : "Unable to read manifest"); }
  const parsed = AudioManifestSchema.safeParse(raw);
  if (!parsed.success) {
    for (const schemaIssue of parsed.error.issues) {
      issue(
        issues,
        "MANIFEST_SCHEMA_INVALID",
        schemaIssue.path.map((segment) => typeof segment === "symbol" ? segment.description ?? "symbol" : segment),
        schemaIssue.message,
      );
    }
  }
  const manifest = asManifest(raw);
  const ids = {
    music: manifest.music.map((entry) => typeof entry?.id === "string" ? entry.id : ""),
    sfx: manifest.sfx.map((entry) => typeof entry?.id === "string" ? entry.id : ""),
    voice: manifest.voice.map((entry) => typeof entry?.id === "string" ? entry.id : ""),
  };
  if (JSON.stringify(ids.music) !== JSON.stringify(MUSIC_IDS)) issue(issues, "MUSIC_IDS_INVALID", ["music"], "Music IDs or order differ from the contract");
  if (JSON.stringify(ids.sfx) !== JSON.stringify(SFX_IDS)) issue(issues, "SFX_IDS_INVALID", ["sfx"], "SFX IDs or order differ from the contract");
  if (JSON.stringify(ids.voice) !== JSON.stringify(VOICE_IDS)) issue(issues, "VOICE_IDS_INVALID", ["voice"], "Voice IDs or order differ from the contract");
  if (!exactStringRecord(manifest.instructionVoice.activityDialogueMap, ACTIVITY_DIALOGUE_MAP)) issue(issues, "INSTRUCTION_DIALOGUE_MAP_INVALID", ["instructionVoice", "activityDialogueMap"], "Activity dialogue routing differs from the reviewed map");
  if (manifest.voiceModel.url !== VOICE_MODEL_URL || manifest.voiceModel.revision !== VOICE_MODEL_REVISION) issue(issues, "VOICE_MODEL_PIN_INVALID", ["voiceModel"], "Voice model URL/revision differs from the reviewed pin");
  for (const [index, entry] of manifest.voice.entries()) {
    if (!isRecord(entry) || typeof entry.id !== "string") continue;
    const expectedPolicy = VOICE_POLICY_BY_ID[entry.id as (typeof VOICE_IDS)[number]];
    if (entry.autoplay !== expectedPolicy) issue(issues, "VOICE_AUTOPLAY_POLICY_INVALID", ["voice", index, "autoplay"], `${entry.id} has an unsafe or mismatched autoplay policy`);
  }
  const allEntries = [...manifest.music, ...manifest.sfx, ...manifest.voice];
  const identityRecords = allEntries.filter(isRecord);
  if (
    identityRecords.length !== allEntries.length
    || new Set(identityRecords.map((entry) => entry.id)).size !== identityRecords.length
    || new Set(identityRecords.map((entry) => entry.path)).size !== identityRecords.length
    || new Set(identityRecords.map((entry) => entry.serial)).size !== identityRecords.length
  ) issue(issues, "DUPLICATE_AUDIO_IDENTITY", [], "Audio IDs, paths, and serials must be present and unique");
  let licenses = "";
  try { licenses = await readFile(options.licensesPath, "utf8"); }
  catch { issue(issues, "LICENSE_LEDGER_MISSING", [], "Unable to read ASSET_LICENSES.md"); }
  let filesChecked = 0;
  for (const [kind, entries] of [["music", manifest.music], ["sfx", manifest.sfx], ["voice", manifest.voice]] as const) {
    for (const [index, entry] of entries.entries()) {
      if (await validateEntry(options.root, entry, kind, index, licenses, manifest.voiceModel, options.technical, issues)) filesChecked += 1;
    }
  }
  try {
    const csv = parseCsv(await readFile(path.join(options.root, "assets/source/audio/dialogue-ko-KR.csv"), "utf8"));
    validateDialogueRows(csv, manifest, issues);
  } catch (error) {
    issue(issues, "DIALOGUE_CSV_MISSING", ["voice"], error instanceof Error ? error.message : "Dialogue delivery CSV is missing");
  }
  return { issues, filesChecked, ids, manifest };
}

async function cli(): Promise<void> {
  const args = process.argv.slice(2);
  const value = (flag: string) => args[args.indexOf(flag) + 1];
  const root = process.cwd();
  const report = await validateAudioWorkspace({
    root,
    manifestPath: path.resolve(root, value("--manifest") ?? "assets/audio/audio-manifest.json"),
    licensesPath: path.resolve(root, value("--licenses") ?? "ASSET_LICENSES.md"),
    technical: !args.includes("--no-technical"),
  });
  if (report.issues.length) {
    for (const item of report.issues) console.error(`${item.code} ${item.path.join("/")}: ${item.message}`);
    process.exitCode = 1;
  } else console.log(`Audio validation passed: ${report.filesChecked} files`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await cli();
