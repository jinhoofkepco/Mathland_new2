# Mathland

Mathland is the Godot redesign of SeoaQuiz: a portrait-first, offline-capable math exploration game for young children. The current foundation includes PIN-gated child profiles, the exploration-island shell, deterministic ten-rod addition, three-heart runs, durable rewards/progress, lifecycle resume, tactile feedback, and Korean/English UI.

## Requirements

- Godot `4.7.1.stable.official.a13da4feb`.
- The Compatibility renderer configured by `project.godot`.
- macOS commands below expect Godot at `/opt/homebrew/bin/godot`.

No live Supabase project, API key, account, or other cloud credential is required to launch or test the offline slice. Sync reports queued local events through `OfflineSyncService`; the authenticated implementation is supplied later behind the same port.

## Open and run

From the repository root:

```bash
/opt/homebrew/bin/godot --editor --path .
```

Run the child app directly:

```bash
/opt/homebrew/bin/godot --path .
```

Create a child profile, choose a four-digit PIN, unlock it, open **자유 탐험**, and select the ten-rod activity. The activity and all required content run offline. Voice is optional and never blocks input; the speaker button is the only question/tutorial replay trigger.

## Tests

```bash
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite all
```

The test runner is repository-owned and needs no Godot test plugin. The all-suite command covers unit, scene, and integration tests, including deterministic persistence/replay, all route viewports, accessibility targets, reduced motion, offline loading, and tactile input latency.

## Offline persistence and resume

Events are flushed before run/progress presentation advances. Active runs checkpoint on application pause and Android back; after the next PIN verification, the same session and question resume without a duplicate event. Completed runs remove their checkpoint while retaining earned rewards.

Profile data lives under `user://profiles/<profile_id>/`. Back up the complete profile directory before manual recovery. See [Godot foundation architecture](docs/architecture/godot-foundation.md) for file ownership, event fields, quarantine behavior, route mapping, and recovery commands.
