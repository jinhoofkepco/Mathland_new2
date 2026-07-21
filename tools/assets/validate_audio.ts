import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

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

type AudioKind = "music" | "sfx" | "voice";

export interface AudioEntry {
  id: string;
  kind: AudioKind;
  path: string;
  bus: "Music" | "SFX" | "Voice";
  channels: number;
  targetLufs: number;
  maxDurationSeconds?: number;
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
  questionNarration: {
    autoplay: boolean;
    trigger: string;
    blocksInput: boolean;
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

function asManifest(value: unknown): AudioManifest {
  const raw = isRecord(value) ? value : {};
  return {
    schemaVersion: typeof raw.schemaVersion === "number" ? raw.schemaVersion : 0,
    sampleRate: typeof raw.sampleRate === "number" ? raw.sampleRate : 0,
    questionNarration: isRecord(raw.questionNarration) ? raw.questionNarration as AudioManifest["questionNarration"] : { autoplay: true, trigger: "", blocksInput: true },
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
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

async function validateEntry(
  root: string,
  entry: AudioEntry,
  kind: AudioKind,
  index: number,
  licenses: string,
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
  if (entry.redistribution !== "confirmed" || !licenses.includes(entry.licenseId) || !licenses.includes(entry.id)) {
    issue(issues, "RIGHTS_UNCONFIRMED", basePath, `${entry.id} requires a confirmed ledger record and license ID`);
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
  if (!technical) return true;
  try {
    const probeText = runText("ffprobe", ["-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:stream_tags=LOOPSTART,LOOPEND:format=duration,format_name", "-of", "json", absolute]);
    const probe = JSON.parse(probeText) as { streams?: Array<{ codec_name?: string; sample_rate?: string; channels?: number; tags?: Record<string, string> }>; format?: { duration?: string; format_name?: string } };
    const stream = probe.streams?.[0];
    const duration = Number(probe.format?.duration);
    if (stream?.codec_name !== "vorbis" || !probe.format?.format_name?.includes("ogg")) issue(issues, "CODEC_INVALID", basePath, `${entry.id} is not Ogg Vorbis`);
    if (Number(stream?.sample_rate) !== 48_000) issue(issues, "SAMPLE_RATE_INVALID", basePath, `${entry.id} is not 48 kHz`);
    if (stream?.channels !== entry.channels) issue(issues, "CHANNEL_INVALID", basePath, `${entry.id} decoded channel count differs`);
    if (!Number.isFinite(duration) || duration <= 0 || (entry.maxDurationSeconds !== undefined && duration > entry.maxDurationSeconds + 0.02)) issue(issues, "DURATION_INVALID", basePath, `${entry.id} duration is outside its limit`);
    if (kind === "music") {
      if (stream?.tags?.LOOPSTART !== String(entry.loopStartSamples) || stream?.tags?.LOOPEND !== String(entry.loopEndSamples)) issue(issues, "LOOP_METADATA_INVALID", basePath, `${entry.id} loop comments differ from the manifest`);
      if (Math.abs(duration * 48_000 - (entry.loopEndSamples ?? 0)) > 2) issue(issues, "LOOP_DURATION_INVALID", basePath, `${entry.id} decoded duration differs from its loop end`);
    }
    const levels = measure(absolute);
    if ((kind === "music" || kind === "voice") && Math.abs(levels.lufs - entry.targetLufs) > 2) issue(issues, "LOUDNESS_INVALID", basePath, `${entry.id} measured ${levels.lufs} LUFS`);
    if (levels.peakDbfs > (kind === "sfx" ? -0.5 : -1)) issue(issues, "PEAK_INVALID", basePath, `${entry.id} true peak is ${levels.peakDbfs} dBFS`);
    const decoded = decode(absolute);
    if (kind === "music" && seamDbfs(decoded, entry.channels) >= -50) issue(issues, "LOOP_SEAM_INVALID", basePath, `${entry.id} loop seam exceeds -50 dBFS`);
    if (kind === "voice" && leadingSilenceSeconds(decoded, entry.channels) >= 0.15) issue(issues, "VOICE_LEADING_SILENCE", basePath, `${entry.id} leading silence is too long`);
  } catch (error) {
    issue(issues, "TECHNICAL_INSPECTION_FAILED", basePath, error instanceof Error ? error.message : `${entry.id} inspection failed`);
  }
  return true;
}

export async function validateAudioWorkspace(options: AudioValidationOptions): Promise<AudioValidationReport> {
  const issues: AudioIssue[] = [];
  let raw: unknown = {};
  try { raw = JSON.parse(await readFile(options.manifestPath, "utf8")); }
  catch (error) { issue(issues, "MANIFEST_READ_FAILED", [], error instanceof Error ? error.message : "Unable to read manifest"); }
  const manifest = asManifest(raw);
  const ids = { music: manifest.music.map((entry) => entry.id), sfx: manifest.sfx.map((entry) => entry.id), voice: manifest.voice.map((entry) => entry.id) };
  if (JSON.stringify(ids.music) !== JSON.stringify(MUSIC_IDS)) issue(issues, "MUSIC_IDS_INVALID", ["music"], "Music IDs or order differ from the contract");
  if (JSON.stringify(ids.sfx) !== JSON.stringify(SFX_IDS)) issue(issues, "SFX_IDS_INVALID", ["sfx"], "SFX IDs or order differ from the contract");
  if (JSON.stringify(ids.voice) !== JSON.stringify(VOICE_IDS)) issue(issues, "VOICE_IDS_INVALID", ["voice"], "Voice IDs or order differ from the contract");
  if (manifest.schemaVersion !== 1 || manifest.sampleRate !== 48_000) issue(issues, "MANIFEST_VERSION_INVALID", [], "Audio manifest version/sample rate is invalid");
  if (manifest.questionNarration.autoplay !== false || manifest.questionNarration.trigger !== "speaker_control_only" || manifest.questionNarration.blocksInput !== false) issue(issues, "QUESTION_VOICE_POLICY", ["questionNarration"], "Question narration must be speaker-only and non-blocking");
  const allEntries = [...manifest.music, ...manifest.sfx, ...manifest.voice];
  if (new Set(allEntries.map((entry) => entry.id)).size !== allEntries.length || new Set(allEntries.map((entry) => entry.path)).size !== allEntries.length || new Set(allEntries.map((entry) => entry.serial)).size !== allEntries.length) issue(issues, "DUPLICATE_AUDIO_IDENTITY", [], "Audio IDs, paths, and serials must be unique");
  let licenses = "";
  try { licenses = await readFile(options.licensesPath, "utf8"); }
  catch { issue(issues, "LICENSE_LEDGER_MISSING", [], "Unable to read ASSET_LICENSES.md"); }
  let filesChecked = 0;
  for (const [kind, entries] of [["music", manifest.music], ["sfx", manifest.sfx], ["voice", manifest.voice]] as const) {
    for (const [index, entry] of entries.entries()) {
      if (await validateEntry(options.root, entry, kind, index, licenses, options.technical, issues)) filesChecked += 1;
    }
  }
  try {
    const csv = parseCsv(await readFile(path.join(options.root, "assets/source/audio/dialogue-ko-KR.csv"), "utf8"));
    const header = csv.shift();
    if (header?.join(",") !== "id,text,pronunciation_notes,max_duration_seconds,skippable,autoplay_policy,speaker_replay" || JSON.stringify(csv.map((row) => row[0])) !== JSON.stringify(VOICE_IDS) || csv.some((row) => row[4] !== "true" || row[6] !== "true")) issue(issues, "DIALOGUE_CSV_INVALID", ["voice"], "Dialogue CSV IDs/policies differ from the manifest contract");
  } catch { issue(issues, "DIALOGUE_CSV_MISSING", ["voice"], "Dialogue delivery CSV is missing"); }
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
