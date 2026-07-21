# MathLand audio delivery specification

All release audio is 48 kHz Ogg Vorbis. Music is stereo; SFX and Korean guide voice are mono. The three music tracks are designed as quiet seamless context loops, and combo feedback layers over the loop instead of restarting it. SFX begin immediately and are intentionally rounded rather than sharp so repeated practice remains comfortable.

The nine Korean guide lines use one warm adult female synthetic guide voice. Every clip is skippable and replayable. Home/tutorial/reward/level-up clips may play only under their listed one-time or event policy and only when the caller explicitly authorizes autoplay; the default is silent. The in-activity speaker replays the current activity's tutorial/instruction clip. It does not claim to narrate a dynamic mathematical expression, and voice playback never disables input or progression.

Music and SFX are original deterministic synthesis authored for MathLand by the project. Release voice is generated with the Ppaso-TTS v8 Korean single-female model at exact revision `53d09664c4f636a5fb6f2ebe3ec22cd83ee249b9` from `https://huggingface.co/akamotaco/ppaso-tts-v1`, after review of its Apache-2.0 model card and synthetic-training provenance. Model weights are external build inputs only and are not bundled. macOS system voices and audition files are prohibited from `assets/audio/`.

Reproduction requires Python with `numpy`, `soundfile`, `python-mecab-ko`, and `onnxruntime`, plus `ffmpeg` and `oggenc`. From the repository root, run `python tools/assets/generate_ppaso_voice.py --model-dir <pinned-model-checkout>`. The generator rejects every other revision, applies the release loudness/peak/duration gates, encodes fixed Ogg serials, and updates the checked-in SHA-256 values. The voice is synthetic and is not presented as a real person.

Targets:

- music: −20 ±2 LUFS, true peak at or below −1 dBFS;
- voice: −18 ±2 LUFS, true peak at or below −1 dBFS, leading silence under 150 ms;
- SFX: each manifest row declares a measured full-clip RMS target with a strict tolerance, remains under 2 s except `level_up` and `reward` under 4 s, and has true peak at or below −0.5 dBFS. Integrated LUFS is intentionally not claimed for these very short effects;
- loop head/tail sample delta: below −50 dBFS after decoding;
- no clip may block input, require network access, or contain a real child's voice.
