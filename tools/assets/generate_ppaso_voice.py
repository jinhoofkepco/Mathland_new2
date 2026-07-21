#!/usr/bin/env python3
"""Generate MathLand's pinned Korean guide voice release files.

The Ppaso model checkout is an external build input. Model weights are never copied
into this repository. This script admits only the reviewed revision and records a
deterministic Ogg serial plus SHA-256 for every release clip.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path


PINNED_MODEL_REVISION = "53d09664c4f636a5fb6f2ebe3ec22cd83ee249b9"
MODEL_URL = "https://huggingface.co/akamotaco/ppaso-tts-v1"
LICENSE_ID = "Ppaso-TTS-v8-Apache-2.0"
SAMPLE_RATE = 48_000


def run(args: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        args,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr.strip()}")
    return (result.stdout or "") + (result.stderr or "")


def measure(path: Path) -> tuple[float, float]:
    output = run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-filter_complex",
            "ebur128=peak=true",
            "-f",
            "null",
            "-",
        ],
        capture=True,
    )
    loudness = re.findall(r"I:\s+(-?[0-9.]+) LUFS", output)
    peaks = re.findall(r"Peak:\s+(-?[0-9.]+) dBFS", output)
    if not loudness or not peaks:
        raise RuntimeError(f"ffmpeg did not emit a loudness summary for {path}")
    return float(loudness[-1]), float(peaks[-1])


def duration_seconds(path: Path) -> float:
    value = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        capture=True,
    ).strip()
    return float(value)


def synthesize_release(
    tts: object,
    soundfile: object,
    text: str,
    entry: dict[str, object],
    root: Path,
    temporary: Path,
) -> None:
    clip_id = str(entry["id"])
    raw_wav = temporary / f"{clip_id}.raw.wav"
    trimmed_wav = temporary / f"{clip_id}.trimmed.wav"
    normalized_wav = temporary / f"{clip_id}.normalized.wav"

    waveform = tts.synthesize(text, chunked=True)
    if len(waveform) == 0 or not all(math.isfinite(float(sample)) for sample in waveform):
        raise RuntimeError(f"{clip_id} synthesis returned invalid samples")
    soundfile.write(str(raw_wav), waveform, 22_050, subtype="PCM_16")

    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(raw_wav),
            "-af",
            (
                "silenceremove=start_periods=1:start_duration=0:"
                "start_threshold=-50dB:stop_periods=-1:stop_duration=0.05:"
                "stop_threshold=-50dB"
            ),
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(trimmed_wav),
        ]
    )
    target_loudness = float(entry["targetLufs"])
    run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(trimmed_wav),
            "-af",
            f"loudnorm=I={target_loudness:.1f}:TP=-1.2:LRA=7:linear=false",
            "-ar",
            str(SAMPLE_RATE),
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(normalized_wav),
        ]
    )

    loudness, peak = measure(normalized_wav)
    if abs(loudness - target_loudness) > 1.0 or peak > -1.0:
        raise RuntimeError(
            f"{clip_id} normalized to {loudness:.1f} LUFS / {peak:.1f} dBFS"
        )

    output = root / str(entry["path"])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    run(
        [
            "oggenc",
            "-Q",
            "-q",
            "5",
            "-s",
            str(entry["serial"]),
            "-t",
            clip_id,
            "-c",
            "LANGUAGE=ko-KR",
            "-c",
            "SYNTHETIC_VOICE=true",
            "-c",
            f"SOURCE_MODEL={MODEL_URL}@{PINNED_MODEL_REVISION}",
            "-c",
            "LICENSE=Apache-2.0",
            "-o",
            str(output),
            str(normalized_wav),
        ]
    )
    duration = duration_seconds(output)
    if duration > float(entry["maxDurationSeconds"]) + 0.02:
        raise RuntimeError(
            f"{clip_id} duration {duration:.3f}s exceeds {entry['maxDurationSeconds']}s"
        )
    entry["sha256"] = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"generated {clip_id}: {duration:.2f}s {entry['sha256']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True, type=Path)
    parser.add_argument("--root", default=Path.cwd(), type=Path)
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    model_dir = arguments.model_dir.resolve()

    actual_revision = run(
        ["git", "-C", str(model_dir), "rev-parse", "HEAD"], capture=True
    ).strip()
    if actual_revision != PINNED_MODEL_REVISION:
        raise RuntimeError(
            f"Ppaso revision {actual_revision} is not pinned {PINNED_MODEL_REVISION}"
        )

    dialogue_path = root / "assets/source/audio/dialogue-ko-KR.csv"
    with dialogue_path.open(encoding="utf-8", newline="") as handle:
        dialogue_rows = list(csv.DictReader(handle))
    texts = {row["id"]: row["text"] for row in dialogue_rows}

    manifest_path = root / "assets/audio/audio-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    voice_entries = manifest["voice"]
    if [entry["id"] for entry in voice_entries] != list(texts):
        raise RuntimeError("Dialogue CSV and voice manifest IDs/order differ")
    if any(entry["licenseId"] != LICENSE_ID for entry in voice_entries):
        raise RuntimeError("Voice manifest does not use the reviewed Ppaso license ID")

    sys.path.insert(0, str(model_dir / "example"))
    ppaso_module = importlib.import_module("ppaso_tts")
    soundfile = importlib.import_module("soundfile")
    tts = ppaso_module.PpasoTTS(model_dir, backend="onnx", device="cpu")

    with tempfile.TemporaryDirectory(prefix="mathland-ppaso-") as temporary_name:
        temporary = Path(temporary_name)
        for entry in voice_entries:
            synthesize_release(
                tts,
                soundfile,
                texts[str(entry["id"])],
                entry,
                root,
                temporary,
            )
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
