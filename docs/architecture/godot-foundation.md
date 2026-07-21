# Godot foundation architecture

This document is the ownership and recovery contract for the offline Godot foundation. The child game must remain playable without a network connection or cloud credential.

## Module ownership

- `src/app/` owns bootstrap, profile activation, route composition, lifecycle notifications, and resume routing. It coordinates services but does not parse persistence files.
- `src/game/` owns run configuration, deterministic state transitions, health/combo/reward rules, and checkpoint adoption. It never opens files or starts network requests.
- `src/ui/` and `scenes/` own presentation and input. They only receive service interfaces through route parameters.
- `src/content/` owns validated activity lookup and deterministic question generation. A run pins one content version until completion.
- `src/persistence/` owns atomic JSON replacement, immutable JSONL events, derived progress snapshots, and profile-scoped run checkpoints.
- `src/progress/` owns deterministic reduction of durable events into a replaceable snapshot.
- `src/sync/` owns the A/C synchronization port. The bundled implementation is deliberately offline and never acknowledges or deletes events.
- `src/presentation/` owns audio, tactile feedback, pooled effects, reduced-motion policy, and no gameplay state.
- `src/profiles/` owns salted PIN verification, child settings, lockout state, and the public profile view.

## Durable answer boundary

An accepted answer follows this order:

1. `RunController.plan_answer` computes an immutable transition without changing the committed run state.
2. `RunSession` projects the transition into an exact `answer_submitted` payload.
3. `EventJournal.append` writes one JSON line, flushes it, closes it, and only then advances the local sequence.
4. A terminal transition writes and flushes `run_completed` before any presentation signal.
5. `RunController.commit` advances the in-memory state.
6. `ProgressService.commit` verifies the same event exists in the journal, reduces it, and atomically replaces `snapshot.json`.
7. Only after those steps do `answer_committed` and `run_completed` update UI, effects, audio, and routing.

An uncertain append or a post-append reducer failure fail-stops the run. A known retry-safe append failure leaves the transition uncommitted and allows a retry.

## `LearningEventV1` exact contract

Unknown top-level fields are rejected. Fields that do not apply to an event are omitted; they are not written as `null`.

Common required fields for every event:

| Field | Type | Nullability |
| --- | --- | --- |
| `contract_version` | integer, exactly `1` | non-null |
| `event_id` | lowercase RFC 4122 UUIDv4 string | non-null |
| `profile_id` | non-empty string | non-null |
| `device_id` | non-empty string | non-null |
| `sequence` | positive safe integer | non-null |
| `client_timestamp` | canonical UTC `YYYY-MM-DDTHH:MM:SSZ` | non-null |
| `event_type` | one of the five event types below | non-null |

`session_id` is the only common optional field. It is required and non-null for `run_started`, `answer_submitted`, and `run_completed`; it may be omitted for collection and coupon events.

Event-specific required, non-null fields:

- `run_started`: `activity_id: string`, `content_version: string`.
- `answer_submitted`: `activity_id: string`, `content_version: string`, `question_seed: non-negative safe integer`, `generator_id: string`, `band_id: string`, `resolved_parameters: object`, `submitted_answer: integer or canonical answer object`, `correct_answer: integer or canonical answer object`, `correctness: boolean`, `response_duration_ms: non-negative safe integer`, `hints: non-negative safe integer`, `health_delta: safe integer`, `combo: non-negative safe integer`, and `reward_delta: non-negative integer map`.
- `run_completed`: `completion_reason: string`, `final_score: non-negative safe integer`, `final_health: non-negative safe integer`, and `earned_rewards: non-negative integer map`.
- `collection_unlocked`: `collection_id: string`.
- `coupon_earned`: `coupon_id: string`.

The TypeScript mirror in `packages/contracts/src/learning-event-v1.ts` must preserve this exact presence/nullability rule.

## A/B content boundary

Subproject A consumes, and Subproject B implements, these stable ports:

- `ContentRepository.get_activity(activity_id: StringName, content_version := "") -> Dictionary`
- `ContentRepository.list_activities() -> Array[Dictionary]`
- `ContentRepository.get_active_version(activity_id: StringName) -> String`
- `ContentRepository.get_manifest_version() -> String`
- `QuestionEngine.generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary`

The generated question carries `activity_id`, pinned `content_version`, `generator_id`, `band_id`, `seed`, and resolved parameters. Resume and journal replay resolve the same immutable content version and regenerate questions from persisted seeds. Content activation or remote updates must never alter an in-progress run.

## A/C synchronization boundary

Subproject C implements authenticated delivery behind `SyncService` without changing game or island callers:

- `status() -> Dictionary` with `{state, pending_count, last_success_at}`.
- `request_sync() -> Dictionary`.
- signal `status_changed(status: Dictionary)`.
- signal `diagnostic(code: String)`.

`OfflineSyncService` reports `{state:"offline", pending_count:<journal event count>, last_success_at:null}`. Its request returns `{ok:false,error:"offline"}` and does not mutate, acknowledge, compact, or delete an event. Runs never wait for synchronization.

## Profile-scoped file layout

```text
user://profiles.json
user://profiles/<profile_id>/
├── events.jsonl
├── snapshot.json
└── run_checkpoint.json
user://content/
```

`run_checkpoint.json` has exactly:

```text
{schema_version:1, profile_id, session_id, content_version, activity_id,
 run_state, current_question, last_event_sequence}
```

It is written through `AtomicJsonStore` using `.tmp` and `.bak` replacement. Pause and Android back notifications first verify the flushed journal and then save the active checkpoint. Completion renames the checkpoint out of the live path and removes it. On PIN-verified startup, an equal journal sequence adopts the checkpoint without emitting an event. A sequence mismatch replays the immutable journal, regenerates questions, refreshes the checkpoint, and never writes a duplicate `run_started` or answer event.

## Quarantine and recovery

- Malformed atomic JSON is renamed to `<name>.corrupt`; a semantic-invalid checkpoint is quarantined the same way.
- An invalid progress snapshot is moved to `snapshot.json.corrupt`, then rebuilt from the valid journal.
- Only an incomplete syntactic final JSONL record is moved to `events.jsonl.partial.corrupt`; the earlier valid prefix is retained. A semantic or sequence error fails closed instead of discarding data.
- Interrupted `.tmp`, `.bak`, recovery, and quarantine rotations are reconciled on the next service configuration. Ambiguous candidates are retained and reported rather than guessed away.
- A checkpoint for an unavailable content version remains in place. The child can use the island, and resume becomes available again when that immutable package is restored.

For diagnosis, preserve the entire single profile directory before changing it. A safe local recovery workflow is:

```bash
cp -R "<Godot user-data>/profiles/<profile_id>" "<backup-directory>/<profile_id>"
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration
```

Do not hand-edit `events.jsonl`, reuse another profile's files, or remove a quarantine artifact before the backup is captured.

## Route map

| Route | Scene |
| --- | --- |
| `profile_select` | `res://scenes/profile/profile_select.tscn` |
| `island` | `res://scenes/island/exploration_island.tscn` |
| `daily_path` | `res://scenes/island/daily_path.tscn` |
| `free_play` | `res://scenes/island/free_play.tscn` |
| `activity_run` | `res://scenes/game/activity_run.tscn` |
| `result` | `res://scenes/game/run_result.tscn` |
| `inventory` | `res://scenes/island/inventory.tscn` |
| `collection` | `res://scenes/island/collection.tscn` |
| `settings` | `res://scenes/island/settings.tscn` |

Cold boot always opens profile selection. A valid PIN activates profile-scoped journal/progress/sync/lifecycle services. A valid checkpoint changes the post-PIN destination to `activity_run`; otherwise it opens the island.

## Standard verification

```bash
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite all
```

The integration suite covers all nine routes at 360×800, 1080×2400, and 800×1280, 48×48 minimum actions, visible action labels, reduced motion, disabled timers, network-free scene loading, lifecycle replay, and 100 synthetic tactile presses with a 100 ms synchronous setup ceiling.
