# Godot Foundation & Game Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, independently testable offline Godot vertical slice from profile selection through Exploration Island, a deterministic ten-rod run, persisted health/rewards, and result/restart flow.

**Architecture:** A composition-root scene wires focused services for routing, profiles, persistence, events, progress, run state, effects, and audio. Game scenes consume immutable content/question contracts and submit intents through `RunSession`; `RunSession` appends a `LearningEventV1` before committing state or emitting presentation signals. Subprojects B and C replace the deterministic content adapter and offline sync adapter without changing scenes or the event payload.

**Tech Stack:** Godot 4.7.1, typed GDScript, Compatibility renderer, repository-owned headless test runner, JSON/JSONL local persistence, GitHub Actions.

## Global Constraints

- Use Godot `4.7.1` and GDScript; use no external Godot test plugin.
- Local test command is `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite <suite>`.
- Android identity is `com.jinhoofkepco.mathland`, version `1.0.0`, version code `1`, minimum SDK `24`, target SDK `35`.
- Use the Compatibility renderer and a `1080x1920` portrait design viewport; layouts use anchors and containers and must render at `360x800`, `1080x2400`, and `800x1280`.
- Play is offline-first. Cloud availability and the offline sync adapter never block profile creation, navigation, runs, rewards, or restart.
- No game scene writes files, calls Supabase, parses raw content, or mutates global progress directly.
- Append the answer event and flush it before committing visual/run progress.
- Default run configuration is three hearts; wrong answers remove health; zero health ends the run while preserving earned rewards.
- Adaptive difficulty is off by default and cannot change rules, rewards, or content version during a run.
- Accepted input begins visible/audio/haptic feedback within `100 ms`; Android interactive targets are at least `48dp` equivalent.
- Reduced-motion mode removes shake and large translation while preserving shape, icon, text, and sound state feedback.
- Korean gameplay copy is centralized in translation resources; scenes contain translation keys, not literal gameplay copy.
- Store only a randomly salted four-digit PIN verifier. Never write or synchronize plaintext PINs.
- Do not request broad external-storage permissions or commit credentials, signing files, learning logs, personal phone numbers, or service-role keys.
- Subproject A uses a deterministic bundled vertical-slice content adapter. Runtime schema validation, production generators, final manipulatives, and migrated activities remain owned by Subproject B.
- The cross-project `LearningEventV1` field contract is frozen in the implementation index; this plan creates its Godot representation and JSON fixtures, and the TypeScript mirror under `packages/contracts/src/` must prove identical field names and nullability.

---

## Planned File Map

- `project.godot`: Godot version, renderer, portrait viewport, application metadata, input actions, and autoload declarations.
- `.github/workflows/godot-tests.yml`: installs the pinned engine and runs headless suites.
- `tests/run_all.gd`, `tests/support/test_case.gd`: repository-owned suite discovery, assertions, exit codes, and deterministic output.
- `src/core/`: clocks, UUIDs, validation results, and composition-root helpers with no UI dependency.
- `src/persistence/`: atomic JSON writes, device identity, snapshots, run checkpoints, and JSONL event storage.
- `src/profiles/`: profile records, salted PIN verification, profile-specific settings, and selection service.
- `src/events/learning_event_v1.gd`: canonical child-app event construction and validation.
- `src/progress/`: pure event reducer plus snapshot/replay orchestration.
- `src/content/`: A/B boundary interfaces and deterministic vertical-slice adapters; B extends this directory.
- `src/game/`: pure run state/controller, persistence-first `RunSession`, and manipulative base API.
- `src/app/`: route constants, router, app composition root, and lifecycle coordinator.
- `src/presentation/`: tactile controls, audio buses/service, pooled effects, and accessibility presentation policy.
- `scenes/`: responsive shell, profile, island, catalogue, settings, run, result, and reusable control/manipulative scenes.
- `resources/i18n/`: centralized Korean and English development translations.
- `resources/content/foundation_ten_rods.vertical_slice.json`: immutable deterministic content fixture for the offline slice.
- `tests/unit/`, `tests/scene/`, `tests/integration/`: logic, instantiated-scene, and full offline-flow suites.

### Task 1: Bootstrap the pinned Godot project and headless test harness

**Files:**
- Create: `project.godot`
- Create: `scenes/app/app_shell.tscn`
- Create: `src/app/app_shell.gd`
- Create: `tests/run_all.gd`
- Create: `tests/support/test_case.gd`
- Create: `tests/unit/test_project_contract.gd`
- Create: `.github/workflows/godot-tests.yml`

**Interfaces:**
- Consumes: none.
- Produces: `TestCase`, suite discovery under `tests/<suite>/`, `AppShell`, and the standard `--suite unit|scene|integration|all` command used by every later task.

- [ ] **Step 1: Add the minimal project and a failing project-contract test**

Create `project.godot` with `config_version=5`, the Compatibility renderer, `1080x1920` viewport, portrait orientation, application version `1.0.0`, and `run/main_scene="res://scenes/app/app_shell.tscn"`. Create `tests/support/test_case.gd` with `assert_true`, `assert_false`, `assert_eq`, `assert_ne`, `assert_null`, and `assert_not_null`; each assertion increments `assertion_count` and appends a readable failure string. Create `tests/run_all.gd` as a `SceneTree` script that recursively loads `test_*.gd` files from the selected suite, awaits each script's `run(tree)` method, prints `PASS <path>` or `FAIL <path>: <message>`, and exits nonzero when any assertion fails.

```gdscript
# tests/unit/test_project_contract.gd
extends TestCase

func run(_tree: SceneTree) -> void:
    assert_eq(ProjectSettings.get_setting("application/config/version"), "1.0.0")
    assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
    assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1080)
    assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1920)
    assert_not_null(load("res://scenes/app/app_shell.tscn"), "main scene must load")
```

- [ ] **Step 2: Run the unit suite and verify the bootstrap test fails**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` and `FAIL res://tests/unit/test_project_contract.gd: main scene must load` because the shell scene does not exist yet.

- [ ] **Step 3: Add the smallest loadable shell**

```gdscript
# src/app/app_shell.gd
class_name AppShell
extends Control

@onready var route_host: Control = %RouteHost

func _ready() -> void:
    set_process_unhandled_input(true)
```

Create `scenes/app/app_shell.tscn` with `AppShell` as a full-rect root, a full-rect `MarginContainer` named `SafeArea`, and a full-rect child `Control` named `RouteHost` with `unique_name_in_owner=true`. Set `project.godot` features to Godot 4.7, `display/window/handheld/orientation=1`, `display/window/stretch/mode="canvas_items"`, and the two renderer keys to `gl_compatibility`.

- [ ] **Step 4: Run the pinned tests and verify a clean pass**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`, one `PASS res://tests/unit/test_project_contract.gd`, and `RESULT PASS tests=1`.

- [ ] **Step 5: Add CI using the identical runner contract**

Create `.github/workflows/godot-tests.yml` to download `Godot_v4.7.1-stable_linux.x86_64.zip` from the official `godotengine/godot` GitHub release, install it as `$RUNNER_TEMP/godot`, export that directory to `PATH`, assert that `godot --version` starts with `4.7.1`, and run suites `unit`, `scene`, and `integration` as separate steps. Local examples retain `/opt/homebrew/bin/godot`; CI uses the resolved `godot` executable.

- [ ] **Step 6: Commit the bootstrap**

```bash
git add project.godot scenes/app/app_shell.tscn src/app/app_shell.gd tests .github/workflows/godot-tests.yml
git commit -m "chore: bootstrap Godot project and headless tests"
```

### Task 2: Add atomic storage, UUIDs, and persistent device identity

**Files:**
- Create: `src/core/uuid_v4.gd`
- Create: `src/persistence/atomic_json_store.gd`
- Create: `src/persistence/device_identity.gd`
- Create: `tests/unit/test_atomic_json_store.gd`
- Create: `tests/unit/test_device_identity.gd`

**Interfaces:**
- Consumes: `TestCase`.
- Produces: `UuidV4.generate() -> String`, `AtomicJsonStore.save(path, value) -> Error`, `AtomicJsonStore.load(path) -> Dictionary`, and `DeviceIdentity.load_or_create() -> String`.

- [ ] **Step 1: Write failing round-trip, quarantine, and stable-ID tests**

```gdscript
# essential assertions in tests/unit/test_atomic_json_store.gd
var store := AtomicJsonStore.new("user://tests/atomic")
assert_eq(store.save("profile.json", {"nickname": "모아"}), OK)
assert_eq(store.load("profile.json"), {"ok": true, "value": {"nickname": "모아"}})
DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/atomic"))
var broken_file := FileAccess.open("user://tests/atomic/broken.json", FileAccess.WRITE)
broken_file.store_string("{broken")
broken_file.close()
var recovered := store.load("broken.json")
assert_false(recovered.ok)
assert_true(recovered.quarantine_path.ends_with(".corrupt"))
assert_false(FileAccess.file_exists("user://tests/atomic/profile.json.tmp"))

# essential assertions in tests/unit/test_device_identity.gd
var first := DeviceIdentity.new(store).load_or_create()
var second := DeviceIdentity.new(store).load_or_create()
assert_true(UuidV4.is_valid(first))
assert_eq(second, first)
```

- [ ] **Step 2: Run the unit suite and verify missing-class failures**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` with parser errors naming `AtomicJsonStore` and `DeviceIdentity`.

- [ ] **Step 3: Implement atomic replace and UUIDv4 generation**

`AtomicJsonStore.save` must create the parent directory, write `<name>.tmp`, call `flush()`, close the file, remove an existing `<name>.bak`, rename the current file to `<name>.bak`, rename the temporary file to the final name, then remove the backup. `load` must return `{ok, value}` on success; on malformed JSON it must rename the source to `<name>.corrupt` and return `{ok:false, error:"invalid_json", quarantine_path}`. `UuidV4.generate` must use `Crypto.generate_random_bytes(16)`, set RFC 4122 version/variant bits, and render lowercase `8-4-4-4-12` hex.

```gdscript
# src/persistence/device_identity.gd
class_name DeviceIdentity
extends RefCounted

const FILE_NAME := "device.json"
var _store: AtomicJsonStore

func _init(store: AtomicJsonStore) -> void:
    _store = store

func load_or_create() -> String:
    var loaded := _store.load(FILE_NAME)
    if loaded.get("ok", false) and UuidV4.is_valid(loaded.value.get("device_id", "")):
        return loaded.value.device_id
    var device_id := UuidV4.generate()
    assert(_store.save(FILE_NAME, {"schema_version": 1, "device_id": device_id}) == OK)
    return device_id
```

- [ ] **Step 4: Run the unit suite and verify persistence passes**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; both new test files print `PASS`, and no `.tmp` file remains.

- [ ] **Step 5: Commit the persistence primitives**

```bash
git add src/core/uuid_v4.gd src/persistence tests/unit/test_atomic_json_store.gd tests/unit/test_device_identity.gd
git commit -m "feat: add atomic local storage and device identity"
```

### Task 3: Implement isolated profiles, salted PIN verification, and profile settings

**Files:**
- Create: `src/profiles/profile_record.gd`
- Create: `src/profiles/pin_verifier.gd`
- Create: `src/profiles/profile_service.gd`
- Create: `tests/unit/test_profile_service.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `AtomicJsonStore`, `UuidV4`.
- Produces: `ProfileService.create_profile(nickname, avatar_id, pin) -> Dictionary`, `verify_and_select(profile_id, pin, now_unix) -> Dictionary`, `update_settings(profile_id, patch) -> Error`, `selected_profile() -> Dictionary`, and `profiles_changed`/`selection_changed` signals.

- [ ] **Step 1: Write failing profile isolation and security tests**

```gdscript
var service := ProfileService.new(AtomicJsonStore.new("user://tests/profiles"))
var a := service.create_profile("하늘", "moa_sky", "1234")
var b := service.create_profile("바다", "moa_mint", "5678")
assert_true(a.ok and b.ok)
assert_ne(a.profile.profile_id, b.profile.profile_id)
assert_eq(service.update_settings(a.profile.profile_id, {"reduced_motion": true}), OK)
assert_false(service.get_profile(b.profile.profile_id).settings.reduced_motion)
var raw := service.read_index_for_test()
assert_false(raw.contains("1234"), "plaintext PIN must never be stored")
for attempt in range(5):
    service.verify_and_select(a.profile.profile_id, "0000", 1000)
assert_eq(service.verify_and_select(a.profile.profile_id, "1234", 1001).error, "pin_locked")
assert_true(service.verify_and_select(a.profile.profile_id, "1234", 1031).ok)
```

- [ ] **Step 2: Run tests and verify `ProfileService` is missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` with `Identifier "ProfileService" not declared`.

- [ ] **Step 3: Implement exact profile and PIN rules**

`ProfileRecord` serializes `profile_id`, trimmed nickname of 1–16 Unicode code points, avatar allowlist `moa_mint|moa_sky|moa_coral`, base64 salt, SHA-256 verifier, failed-attempt count, lock deadline, settings, and creation timestamp. Settings defaults are:

```gdscript
const DEFAULT_SETTINGS := {
    "adaptive_difficulty": false,
    "timing_aids": true,
    "timers_enabled": true,
    "reduced_motion": false,
    "effect_quality": "high",
    "master_db": 0.0,
    "music_db": -6.0,
    "sfx_db": 0.0,
    "voice_db": 0.0,
    "voice_enabled": true,
}
```

`PinVerifier` accepts exactly four ASCII digits, creates a 16-byte random salt, hashes `salt + UTF-8 PIN` with SHA-256, and compares verifier bytes without an early return. Five failures lock that profile for 30 seconds; a successful verification clears failure state. `ProfileService` extends `Node`, accepts an optional injected store in `_init(store: AtomicJsonStore = null)`, uses `user://` when no store is injected, atomically writes `user://profiles.json` after every mutation, and keeps progress files outside that index.

- [ ] **Step 4: Register and exercise the profile service**

Add `ProfileService="*res://src/profiles/profile_service.gd"` to `[autoload]`. Run the unit suite.

Expected: exit `0`; `test_profile_service.gd` passes, the stored JSON contains `pin_salt` and `pin_verifier`, and it contains neither tested plaintext PIN.

- [ ] **Step 5: Commit profile support**

```bash
git add project.godot src/profiles tests/unit/test_profile_service.gd
git commit -m "feat: add secure isolated child profiles"
```

### Task 4: Define `LearningEventV1` and a crash-tolerant append-only journal

**Files:**
- Create: `src/events/learning_event_v1.gd`
- Create: `src/persistence/event_journal.gd`
- Create: `tests/fixtures/contracts/learning_event_v1.json`
- Create: `tests/unit/test_learning_event_v1.gd`
- Create: `tests/unit/test_event_journal.gd`

**Interfaces:**
- Consumes: `UuidV4`, selected profile/device IDs.
- Produces: `LearningEventV1.create(context, payload) -> Dictionary`, `validate(event) -> PackedStringArray`, and `EventJournal.append(payload) -> Dictionary`, `replay() -> Dictionary`, `unacknowledged(after_sequence, limit := 100) -> Array[Dictionary]`.

- [ ] **Step 1: Add failing contract and recovery tests**

Use this exact fixture shape in `tests/fixtures/contracts/learning_event_v1.json` and assert it validates:

```json
{"contract_version":1,"event_id":"1ebc4ec2-9c32-4f7d-9c3c-d21c284d7a31","profile_id":"profile-a","device_id":"device-a","session_id":"session-a","sequence":1,"client_timestamp":"2026-07-21T09:00:00Z","event_type":"answer_submitted","activity_id":"foundation_ten_rods","content_version":"a-vertical-1","question_seed":42,"generator_id":"foundation_ten_rods","band_id":"count_to_10","resolved_parameters":{"left":3,"right":4},"submitted_answer":7,"correct_answer":7,"correctness":true,"response_duration_ms":1200,"hints":0,"health_delta":0,"combo":1,"reward_delta":{"apples":2}}
```

The journal test must append two payloads, assert sequences `1,2`, reopen and replay them, append an invalid unterminated final line, reopen again, assert the first two events survive, and assert the tail is moved to `events.jsonl.partial.corrupt`. Assert `unacknowledged(0, 100)` returns ascending sequence order.

- [ ] **Step 2: Run tests and verify event classes are missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` with missing `LearningEventV1` and `EventJournal` identifiers.

- [ ] **Step 3: Implement the contract without arbitrary payload fields**

`LearningEventV1` must allow event types `run_started`, `answer_submitted`, `run_completed`, `collection_unlocked`, and `coupon_earned`; require the common identity/order fields; require all question/reward fields for `answer_submitted`; and reject unknown top-level keys. Fields not applicable to an event are omitted, not serialized as invented defaults. `EventJournal.configure(profile_id, device_id, path)` scans the valid prefix to recover the next sequence. `append` constructs the event, writes one compact JSON line plus newline, calls `flush()`, and only then advances `_next_sequence`.

```gdscript
func append(payload: Dictionary) -> Dictionary:
    var event := LearningEventV1.create({
        "profile_id": _profile_id,
        "device_id": _device_id,
        "sequence": _next_sequence,
    }, payload)
    var errors := LearningEventV1.validate(event)
    if not errors.is_empty():
        return {"ok": false, "error": "invalid_event", "details": errors}
    var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE_READ
    var file := FileAccess.open(_path, mode)
    if file == null:
        return {"ok": false, "error": "journal_open_failed"}
    file.seek_end()
    file.store_line(JSON.stringify(event, "", false))
    file.flush()
    _next_sequence += 1
    return {"ok": true, "event": event}
```

- [ ] **Step 4: Run contract and journal tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; the fixture and two journal tests pass, and replay reports `quarantined_tail=true` only for the malformed final record.

- [ ] **Step 5: Commit the event contract**

```bash
git add src/events src/persistence/event_journal.gd tests/fixtures/contracts tests/unit/test_learning_event_v1.gd tests/unit/test_event_journal.gd
git commit -m "feat: add durable LearningEventV1 journal"
```

### Task 5: Derive and snapshot profile progress from events

**Files:**
- Create: `src/progress/progress_reducer.gd`
- Create: `src/progress/progress_service.gd`
- Create: `tests/unit/test_progress_reducer.gd`
- Create: `tests/unit/test_progress_service.gd`

**Interfaces:**
- Consumes: valid `LearningEventV1` dictionaries, `AtomicJsonStore`, `EventJournal.replay()`.
- Produces: `ProgressReducer.initial_state(profile_id) -> Dictionary`, `apply(state, event) -> Dictionary`, and `ProgressService.load_profile(profile_id, journal)`, `commit(event) -> Error`, `snapshot() -> Dictionary`.

- [ ] **Step 1: Write failing reducer and replay tests**

Assert that two correct answer events with `reward_delta.apples=2`, one wrong answer event, and a zero-health `run_completed` event produce apples `4`, correct `2`, attempts `3`, health-depletion runs `1`, pending review `1`, and last applied sequence `4`. Corrupt `snapshot.json`, load the service, and assert the valid journal replays to the same state and the corrupt snapshot is quarantined.

- [ ] **Step 2: Run tests and verify reducer classes are missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` naming `ProgressReducer` and `ProgressService`.

- [ ] **Step 3: Implement a pure reducer and versioned snapshot**

The snapshot schema is `{schema_version:1, profile_id, last_sequence, apples, inventory, collections, coupons, pending_review, activity_progress, run_totals}`. `answer_submitted` increments attempts/correctness, applies nonnegative reward deltas, records repeated-error keys, and increments pending review for wrong answers. `run_completed` increments completion or health-depletion totals. Duplicate or older sequences return an unchanged deep copy. `ProgressService.commit` applies one already-journaled event, writes `user://profiles/<profile_id>/snapshot.json` atomically, and publishes `progress_changed` only after the write succeeds.

- [ ] **Step 4: Run reducer/recovery tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; reducer and corrupt-snapshot replay tests pass, including the preserved apple balance after health depletion.

- [ ] **Step 5: Commit progress derivation**

```bash
git add src/progress tests/unit/test_progress_reducer.gd tests/unit/test_progress_service.gd
git commit -m "feat: derive profile progress from durable events"
```

### Task 6: Lock the content, question, and manipulative boundaries

**Files:**
- Create: `src/content/content_repository.gd`
- Create: `src/content/question_engine.gd`
- Create: `src/content/vertical_slice_content_repository.gd`
- Create: `src/content/vertical_slice_question_engine.gd`
- Create: `src/game/manipulatives/manipulative.gd`
- Create: `resources/content/foundation_ten_rods.vertical_slice.json`
- Create: `tests/unit/test_content_contracts.gd`
- Create: `tests/unit/test_vertical_slice_question_engine.gd`

**Interfaces:**
- Consumes: none; these are the stable A/B boundaries.
- Produces: `ContentRepository.get_activity(activity_id: StringName, content_version := "") -> Dictionary`, `list_activities() -> Array[Dictionary]`, `get_active_version(activity_id: StringName) -> String`, `get_manifest_version() -> String`, `QuestionEngine.generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary`, and the `Manipulative` API below.

- [ ] **Step 1: Write failing boundary and determinism tests**

Assert `get_activity(&"foundation_ten_rods")` returns a deep copy with version `a-vertical-1`; mutating the returned copy must not alter the next read. Generate twice with seed `42` and assert identical questions; seed `43` must produce a different `resolved_parameters` tuple while remaining in `0..10`. Assert every generated dictionary has `question_id`, `activity_id`, `content_version`, `generator_id`, `band_id`, `seed`, `resolved_parameters`, `prompt_key`, `correct_answer`, `answer_layout`, and `manipulative`.

- [ ] **Step 2: Run unit tests and verify missing contract classes**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` naming `ContentRepository`, `QuestionEngine`, and `Manipulative`.

- [ ] **Step 3: Implement the exact interfaces and deterministic adapter**

```gdscript
# src/game/manipulatives/manipulative.gd
class_name Manipulative
extends Control

signal state_changed(state: Dictionary)
signal answer_submitted(answer: Variant)

func configure(config: Dictionary, question: Dictionary) -> void:
    assert(false, "configure must be overridden")

func reset_state() -> void:
    assert(false, "reset_state must be overridden")

func set_interaction_enabled(enabled: bool) -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func get_answer_state() -> Dictionary:
    return {}

func apply_answer_state(_state: Dictionary) -> void:
    assert(false, "apply_answer_state must be overridden")
```

The bundled JSON defines one activity with health `3`, target `5`, timer disabled, two apples per correct answer, band `count_to_10`, generator `foundation_ten_rods`, and scene allowlist entry `res://scenes/game/manipulatives/ten_rod_board.tscn`. `VerticalSliceQuestionEngine` seeds a local `RandomNumberGenerator`, chooses `left` and `right` so their sum is `1..10`, and returns the full dictionary asserted above. It does not evaluate expressions or load arbitrary scenes.

- [ ] **Step 4: Run content-boundary tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; content copies are isolated and both seed determinism assertions pass.

- [ ] **Step 5: Commit the A/B contracts**

```bash
git add src/content src/game/manipulatives/manipulative.gd resources/content tests/unit/test_content_contracts.gd tests/unit/test_vertical_slice_question_engine.gd
git commit -m "feat: define content question and manipulative contracts"
```

### Task 7: Implement deterministic run state, health, combo, timer, and pause

**Files:**
- Create: `src/core/clock.gd`
- Create: `src/core/system_clock.gd`
- Create: `tests/support/fake_clock.gd`
- Create: `src/game/run_config.gd`
- Create: `src/game/run_state.gd`
- Create: `src/game/run_transition.gd`
- Create: `src/game/run_controller.gd`
- Create: `tests/unit/test_run_controller.gd`

**Interfaces:**
- Consumes: immutable activity/question dictionaries and injected `Clock`.
- Produces: `RunController.start(config, session_id)`, `begin_question(question)`, `plan_answer(answer, response_ms, hints) -> RunTransition`, `plan_timeout() -> RunTransition`, `commit(transition)`, `pause()`, `resume()`, and `time_remaining_ms()`.

- [ ] **Step 1: Write failing state-transition tests**

Test a three-heart, target-two run: a correct answer raises score/combo and grants two apples without health loss; a wrong answer resets combo and changes health by `-1`; three wrong answers produce `completion_reason="health_depleted"`; a second correct answer produces `completion_reason="target_reached"`. Mark the target question as a boss and assert its transition uses `boss`; commit a target-reaching transition and assert the follow-up completion preset is `level_up`. With timer `0`, advancing the fake clock never times out. With timer `5000`, pausing at `2000`, advancing ten seconds, and resuming leaves `3000` milliseconds.

- [ ] **Step 2: Run tests and verify `RunController` is missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` with `Identifier "RunController" not declared`.

- [ ] **Step 3: Implement preview-then-commit transitions**

`RunConfig` contains stage ID, boss-question indices, initial health, target score, timer permission/duration, reward deltas, combo thresholds, and effect intensity. `RunState` contains session/activity/content/stage IDs, health, score, combo, question index, current question/seed, boss state, earned rewards, pause/timer state, completion reason, and status. `plan_answer` deep-copies state, compares canonical values, calculates health/combo/reward/effect name, and returns a `RunTransition` without mutating current state. `commit` rejects a transition whose `from_revision` differs from the current revision, then replaces state and increments revision. Effect names are `correct`, `wrong`, `combo_1`, `combo_2`, `boss`, `health_loss`, `target_reached`, `level_up`, and `health_depleted`.

- [ ] **Step 4: Run run-controller tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; all health, target, combo, disabled-timer, and pause assertions pass.

- [ ] **Step 5: Commit the pure game core**

```bash
git add src/core/clock.gd src/core/system_clock.gd src/game/run_*.gd tests/support/fake_clock.gd tests/unit/test_run_controller.gd
git commit -m "feat: add deterministic run state machine"
```

### Task 8: Enforce journal-before-visual progression with `RunSession`

**Files:**
- Create: `src/game/run_session.gd`
- Create: `tests/support/recording_journal.gd`
- Create: `tests/support/in_memory_progress_service.gd`
- Create: `tests/unit/test_run_session.gd`

**Interfaces:**
- Consumes: `RunController`, `EventJournal` interface, `ProgressService` interface.
- Produces: `RunSession.start_run(activity, first_question) -> Dictionary`, `submit_answer(answer, response_ms, hints := 0) -> Dictionary`, `expire_question() -> Dictionary`, and signals `answer_committed(event, transition)`, `run_completed(event, state)`, `persistence_failed(code)`.

- [ ] **Step 1: Write a failing ordering and failure-containment test**

Use `RecordingJournal.operations` and connect `answer_committed` to append `"signal"`. Assert one submission records `journal.append`, `progress.commit`, then `signal` in that exact order. Configure the journal to return `{ok:false,error:"disk_full"}`; assert controller revision, health, score, and combo remain unchanged, no presentation signal fires, and `persistence_failed("disk_full")` fires once.

- [ ] **Step 2: Run tests and verify `RunSession` is missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` with `Identifier "RunSession" not declared`.

- [ ] **Step 3: Implement persistence-first orchestration**

`RunSession.submit_answer` calls `plan_answer`, constructs the exact `answer_submitted` payload from the question and transition, appends and flushes it, commits the controller, commits the reducer snapshot, then emits presentation signals. On terminal state it appends `run_completed` with `completion_reason`, final score/health, and earned rewards before emitting `run_completed`. Any append failure leaves the planned transition uncommitted.

- [ ] **Step 4: Run ordering tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; ordering is exactly `journal.append,progress.commit,signal`, and the disk-failure state is unchanged.

- [ ] **Step 5: Commit the run orchestration boundary**

```bash
git add src/game/run_session.gd tests/support/recording_journal.gd tests/support/in_memory_progress_service.gd tests/unit/test_run_session.gd
git commit -m "feat: persist run events before progression"
```

### Task 9: Add stack-based routing and Android back behavior

**Files:**
- Create: `src/app/app_route.gd`
- Create: `src/app/app_router.gd`
- Create: `tests/unit/test_app_router.gd`
- Modify: `src/app/app_shell.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: a route host `Control` and an allowlisted route-to-`PackedScene` map.
- Produces: `AppRouter.navigate(route, params := {})`, `replace(route, params := {})`, `back() -> bool`, `current_route() -> StringName`, `current_params() -> Dictionary`, and `route_changed` signal.

- [ ] **Step 1: Write failing push, replace, and back tests**

Assert the route sequence `PROFILE_SELECT → ISLAND → FREE_PLAY`, one back returns to `ISLAND`, replace with `RESULT` does not grow the stack, and an unknown route returns `{ok:false,error:"unknown_route"}` without changing the current scene.

- [ ] **Step 2: Run tests and verify router classes are missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` naming `AppRouter` and `AppRoute`.

- [ ] **Step 3: Implement the route allowlist and shell integration**

Define routes `PROFILE_SELECT`, `ISLAND`, `DAILY_PATH`, `FREE_PLAY`, `ACTIVITY_RUN`, `RESULT`, `INVENTORY`, `COLLECTION`, and `SETTINGS`. `AppRouter` frees only the outgoing route node, instantiates only registered `PackedScene` values, calls `configure(params)` when present, and retains route/parameter records for back navigation. `AppShell._unhandled_input` handles `ui_cancel`; at the root profile route it delegates to the platform instead of creating duplicate screens.

- [ ] **Step 4: Run router tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `0`; route stack and unknown-route containment tests pass.

- [ ] **Step 5: Commit navigation**

```bash
git add project.godot src/app tests/unit/test_app_router.gd
git commit -m "feat: add allowlisted app routing and back stack"
```

### Task 10: Build the tactile, accessible input control

**Files:**
- Create: `src/presentation/controls/tactile_button.gd`
- Create: `scenes/shared/tactile_button.tscn`
- Create: `tests/scene/test_tactile_button.gd`

**Interfaces:**
- Consumes: profile reduced-motion setting and named SFX callback.
- Produces: `TactileButton` signals `press_started`, `accepted`, `cancelled`, `sfx_requested(id)`; `configure_accessibility(label_key, icon_name)`; minimum size `48x48` logical units.

- [ ] **Step 1: Write a failing scene test for down/release/cancel behavior**

Instantiate the scene, send pointer-down inside bounds, assert `press_started` occurs in the same frame and scale/shadow changes; release inside and assert `accepted`; drag outside then release and assert `cancelled`. Assert `custom_minimum_size.x/y >= 48` and a nonempty accessible text label.

- [ ] **Step 2: Run the scene suite and verify the control is missing**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene`

Expected: exit `1` because `res://scenes/shared/tactile_button.tscn` cannot load.

- [ ] **Step 3: Implement immediate multimodal response**

Use `_gui_input` to begin compression, shadow reduction, `Input.vibrate_handheld(15)`, and emit `sfx_requested(&"button_down")` on pointer down. The composition root connects that request to `AudioService.play_sfx`, allowing this control to be tested before audio is constructed. On release, test `Rect2(Vector2.ZERO, size).has_point(local_position)`, restore with a spring tween, and emit `accepted` or `cancelled`. In reduced motion, change border/shadow without scaling or translation. Visible labels remain present beside icons; color is never the sole accepted/cancelled indicator.

- [ ] **Step 4: Run scene tests**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene`

Expected: exit `0`; all three signals, minimum target, and same-frame feedback assertions pass.

- [ ] **Step 5: Commit the shared input control**

```bash
git add src/presentation/controls scenes/shared/tactile_button.tscn tests/scene/test_tactile_button.gd
git commit -m "feat: add tactile accessible button control"
```

### Task 11: Add pooled named effects with quality and reduced-motion policies

**Files:**
- Create: `src/presentation/effects/effect_catalog.gd`
- Create: `src/presentation/effects/transient_pool.gd`
- Create: `src/presentation/effects/effects_service.gd`
- Create: `src/presentation/effects/effect_burst.gd`
- Create: `scenes/shared/effect_burst.tscn`
- Create: `tests/unit/test_effects_service.gd`
- Create: `tests/scene/test_effect_burst.gd`

**Interfaces:**
- Consumes: effect name, anchor position, quality `low|medium|high`, and reduced-motion Boolean.
- Produces: `EffectsService.play(name: StringName, at: Vector2) -> bool`, `set_policy(quality, reduced_motion)`, and pooled presets for every run-controller effect name.

- [ ] **Step 1: Write failing preset, pool-reuse, and reduced-motion tests**

Assert all names from Task 7 plus `reward`, `collection`, and `coupon` resolve, unknown names return `false`, ten sequential effects reuse pooled nodes after completion, low quality emits at most one quarter of high-quality particles, and reduced motion sets shake/large-translation amplitude to zero while retaining icon/text flash duration.

- [ ] **Step 2: Run unit and scene suites and verify failures**

Run both standard commands with `--suite unit` and `--suite scene`.

Expected: both exit `1`, naming `EffectsService` and the missing burst scene.

- [ ] **Step 3: Implement catalog-driven pooled effects**

`EffectCatalog` returns immutable dictionaries for `correct`, `wrong`, `combo_1`, `combo_2`, `boss`, `health_loss`, `target_reached`, `level_up`, `health_depleted`, `reward`, `collection`, and `coupon`. `TransientPool` prewarms eight `EffectBurst` instances and returns nodes to the pool on `finished`. `EffectsService` applies quality multipliers `0.25`, `0.6`, and `1.0`; reduced motion zeros shake/translation but keeps a brief border/icon flash.

- [ ] **Step 4: Run effects tests**

Run the unit and scene commands again.

Expected: exit `0` for both; pool size stabilizes and reduced-motion assertions pass.

- [ ] **Step 5: Commit the effects layer**

```bash
git add src/presentation/effects scenes/shared/effect_burst.tscn tests/unit/test_effects_service.gd tests/scene/test_effect_burst.gd
git commit -m "feat: add pooled configurable game effects"
```

### Task 12: Add four audio buses and independently controllable voice

**Files:**
- Create: `default_bus_layout.tres`
- Create: `src/presentation/audio/audio_service.gd`
- Create: `src/presentation/audio/tone_factory.gd`
- Create: `tests/unit/test_audio_service.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: profile audio settings and stable dialogue/SFX IDs.
- Produces: `AudioService.apply_settings(settings)`, `play_sfx(id) -> bool`, `play_voice(dialogue_id) -> bool`, `stop_voice()`, `voice_finished(dialogue_id)`, and `voice_missing(dialogue_id)`.

- [ ] **Step 1: Write failing bus and interruption tests**

Assert buses appear in exact order `Master`, `Music`, `SFX`, `Voice`; profile decibel settings apply to the correct bus; starting voice B stops voice A; disabled voice returns `false`; missing dialogue emits `voice_missing`; and SFX works offline through deterministic generated tones.

- [ ] **Step 2: Run tests and verify bus/service failures**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite unit`

Expected: exit `1` because the buses and `AudioService` are absent.

- [ ] **Step 3: Implement audio ownership and nonblocking voice**

Create the four buses in `default_bus_layout.tres`. `AudioService` owns one music, one SFX, and one voice player; `ToneFactory` builds short offline `AudioStreamWAV` tones for `button_down`, `correct`, `wrong`, `health_loss`, and `reward`. Voice uses an allowlisted dialogue registry; an absent clip emits `voice_missing` without delaying input or progression. `stop_voice` is callable from speaker replay, screen change, and profile switch.

- [ ] **Step 4: Run audio tests**

Run the unit command.

Expected: exit `0`; bus routing, volume, interruption, disabled-voice, missing-clip, and offline-tone tests pass.

- [ ] **Step 5: Commit audio services**

```bash
git add project.godot default_bus_layout.tres src/presentation/audio tests/unit/test_audio_service.gd
git commit -m "feat: add offline audio buses and voice control"
```

### Task 13: Build responsive profile, island, catalogue, collection, and settings screens

**Files:**
- Create: `scenes/profile/profile_select.tscn`
- Create: `scenes/profile/profile_create_dialog.tscn`
- Create: `src/ui/profile/profile_select.gd`
- Create: `src/ui/profile/profile_create_dialog.gd`
- Create: `scenes/island/exploration_island.tscn`
- Create: `scenes/island/daily_path.tscn`
- Create: `scenes/island/free_play.tscn`
- Create: `scenes/island/inventory.tscn`
- Create: `scenes/island/collection.tscn`
- Create: `scenes/island/settings.tscn`
- Create: `src/ui/island/exploration_island.gd`
- Create: `src/ui/island/daily_path.gd`
- Create: `src/ui/island/free_play.gd`
- Create: `src/ui/island/inventory.gd`
- Create: `src/ui/island/collection.gd`
- Create: `src/ui/island/settings.gd`
- Create: `src/island/daily_objective_service.gd`
- Create: `resources/i18n/ko.po`
- Create: `resources/i18n/en.po`
- Create: `tests/scene/test_child_shell_screens.gd`
- Modify: `src/app/app_shell.gd`

**Interfaces:**
- Consumes: `ProfileService`, `ProgressService`, `ContentRepository`, `AppRouter`, `AudioService`, `EffectsService`.
- Produces: functional routes with `configure(params)`, visible text labels, three deterministic daily objectives, and profile-specific settings updates.

- [ ] **Step 1: Write failing screen and viewport tests**

For each scene, instantiate at `360x800`, `1080x2400`, and `800x1280`; assert every named primary action lies inside the viewport, has a visible translated label, and has minimum size `48x48`. Profile creation must reject duplicate nickname only within exact normalized match, non-four-digit PINs, and unknown avatars. Island must expose exactly three objectives plus Continue, Daily Path, Free Play, Inventory, Collection, Settings, apple balance, pending review, and offline sync state.

- [ ] **Step 2: Run scene tests and verify missing scenes**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene`

Expected: exit `1` listing the first missing profile/island scene.

- [ ] **Step 3: Implement the responsive scene trees and centralized copy**

Build screens from `MarginContainer`, `VBoxContainer`, `HBoxContainer`, `GridContainer`, and `ScrollContainer`; do not position primary controls with fixed coordinates. Add Korean and English entries for every label key, including profile creation/errors, island actions, objective text, sync offline/queued text, settings, collection empty-state text, and inventory counts. `DailyObjectiveService.objectives(profile_id, yyyy_mm_dd)` hashes the two inputs and selects three distinct objective keys from a fixed allowlist, making the same profile/date stable offline.

- [ ] **Step 4: Connect all routes and settings**

Register each scene with `AppRouter`. Profile selection requires PIN verification before changing selected profile. Settings immediately updates adaptive off/on, timing aids, timer permission, reduced motion, effect quality, four volume levels, and voice enabled; it then calls the audio/effects services. Free Play renders every immutable summary returned by `ContentRepository.list_activities()` and Daily Path's first objective routes to the vertical-slice activity with `source="daily"`.

- [ ] **Step 5: Run scene tests at all three viewports**

Run the scene command.

Expected: exit `0`; all screen-load, route-label, objective, target-size, and no-clipping assertions pass at all three sizes.

- [ ] **Step 6: Commit the child shell screens**

```bash
git add scenes/profile scenes/island src/ui src/island resources/i18n src/app/app_shell.gd tests/scene/test_child_shell_screens.gd
git commit -m "feat: add responsive profile and island experience"
```

### Task 14: Deliver the persisted ten-rod activity, result, and reward vertical slice

**Files:**
- Create: `scenes/game/manipulatives/ten_rod_board.tscn`
- Create: `src/game/manipulatives/ten_rod_board.gd`
- Create: `scenes/game/activity_run.tscn`
- Create: `src/ui/game/activity_run.gd`
- Create: `scenes/game/run_result.tscn`
- Create: `src/ui/game/run_result.gd`
- Create: `scenes/game/reward_overlay.tscn`
- Create: `src/ui/game/reward_overlay.gd`
- Create: `tests/scene/test_ten_rod_board.gd`
- Create: `tests/integration/test_offline_vertical_slice.gd`

**Interfaces:**
- Consumes: contracts from Tasks 4–12 and route params `{activity_id, source, seed?}`.
- Produces: `TenRodBoard` implementation of `Manipulative`, a complete offline run, skip controls, persisted results, immediate restart, and return-to-island flow.

- [ ] **Step 1: Write a failing manipulative contract test**

Configure target `7`; add one rod and three units; assert `get_answer_state()` returns `{tens:1, units:3, value:13}`; reset; apply `{tens:0,units:7,value:7}` and assert the visual count and state match; disabling interaction must prevent mutation. Assert submit emits numeric `7`.

- [ ] **Step 2: Write a failing full offline-flow test**

Create profile, select it, enter island, open Free Play, start with seed `42`, skip the introduction, answer two questions correctly and three incorrectly, and assert: each answer appears in `events.jsonl` before the UI advances; health reaches zero; result reason is `health_depleted`; four apples remain in snapshot; pending review is three; Restart starts the same immutable content version with a new session ID; Island shows the persisted four apples after process restart simulation.

- [ ] **Step 3: Run scene and integration suites and verify failures**

Run the standard scene and integration commands.

Expected: scene exits `1` for the missing ten-rod scene; integration exits `1` for the missing activity route.

- [ ] **Step 4: Implement the ten-rod board**

Use container-based SVG/code-native rectangles with distinct ten/one shapes and text counts. `TenRodBoard` implements every Task 6 method, clamps total to `0..99`, emits state after accepted manipulation, and exposes a labeled Submit `TactileButton`. Its correctness signal includes shape/text; it never reads content files or writes progress.

- [ ] **Step 5: Implement activity, feedback, and result orchestration**

`ActivityRun.configure` resolves one activity version once, generates a deterministic question, creates `RunController`/`RunSession`, and displays a skippable introduction. A visible speaker control replays the current dialogue ID and never blocks input when voice is absent or interrupted. It disables answer input during persistence, then on `answer_committed` updates hearts/combo/score, plays the named effect/SFX, and generates the next question. On `run_completed`, route-replace with Result. `RunResult` shows score, reason, earned apples, review count, island-restoration delta, Restart, and Island. `RewardOverlay` is tappable to skip and uses the `reward`, `collection`, or `coupon` preset according to the persisted reward event.

- [ ] **Step 6: Run the complete slice tests**

Run:

```bash
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite scene
/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite integration
```

Expected: both exit `0`; the integration output includes `PASS res://tests/integration/test_offline_vertical_slice.gd` and the persisted values `apples=4 pending_review=3`.

- [ ] **Step 7: Commit the offline vertical slice**

```bash
git add scenes/game src/game/manipulatives/ten_rod_board.gd src/ui/game tests/scene/test_ten_rod_board.gd tests/integration/test_offline_vertical_slice.gd
git commit -m "feat: deliver persisted offline ten-rod run"
```

### Task 15: Add lifecycle recovery, offline sync status, and final quality gates

**Files:**
- Create: `src/persistence/run_checkpoint_store.gd`
- Create: `src/app/app_lifecycle.gd`
- Create: `src/sync/sync_service.gd`
- Create: `src/sync/offline_sync_service.gd`
- Create: `tests/unit/test_run_checkpoint_store.gd`
- Create: `tests/unit/test_offline_sync_service.gd`
- Create: `tests/integration/test_lifecycle_resume.gd`
- Create: `tests/integration/test_accessibility_and_performance_contract.gd`
- Create: `docs/architecture/godot-foundation.md`
- Modify: `project.godot`
- Create: `README.md`

**Interfaces:**
- Consumes: active `RunSession`, profile ID, event journal, and router.
- Produces: `AppLifecycle.flush_and_checkpoint()`, `restore_if_present() -> Dictionary`, `SyncService.status() -> Dictionary`, and `OfflineSyncService` with pending count and no network dependency.

- [ ] **Step 1: Write failing lifecycle and sync-state tests**

Start seed `42`, answer once, begin the next question, checkpoint on notification, reconstruct services, and assert the same session/content/question seed/state returns without a duplicate `run_started` or question event. Write a checkpoint whose last event sequence disagrees with the journal and assert restore replays the journal rather than trusting the stale checkpoint. Assert offline sync returns `{state:"offline", pending_count:<journal count>, last_success_at:null}` and never prevents `start_run`.

- [ ] **Step 2: Run unit and integration suites and verify failures**

Run the standard unit and integration commands.

Expected: both exit `1`, naming missing checkpoint and offline sync classes.

- [ ] **Step 3: Implement atomic checkpoints and lifecycle notifications**

Checkpoint schema is `{schema_version:1, profile_id, session_id, content_version, activity_id, run_state, current_question, last_event_sequence}` at `user://profiles/<profile_id>/run_checkpoint.json`. On `NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_WM_GO_BACK_REQUEST`, flush the journal and atomically save the checkpoint. Restore validates profile, content version, and journal sequence; mismatch replays journal and reconstructs state. Completion atomically removes the checkpoint.

- [ ] **Step 4: Implement the offline sync port used by the island**

`SyncService` defines `status`, `request_sync`, and signals `status_changed`/`diagnostic`. `OfflineSyncService.request_sync` returns `{ok:false,error:"offline"}` without mutating or deleting events. It reports pending journal count and leaves the last-success time null. Subproject C implements authenticated batching/retry/ack behind this exact interface.

- [ ] **Step 5: Add measurable accessibility/performance contract checks**

The integration test traverses all route scenes at the three approved viewports, checks `48x48` minimum interactive bounds, visible labels, reduced-motion effect policy, timer-disable behavior, and scene load without network. It measures accepted-input feedback over 100 synthetic presses using `Time.get_ticks_usec()` and fails if any synchronous feedback setup exceeds `100000` microseconds; rendering frame-time gates remain in Subproject D on the Android reference profile.

- [ ] **Step 6: Run every test suite from a clean user-data directory**

Run: `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite all`

Expected: exit `0`, no `FAIL` lines, and final `RESULT PASS` covering unit, scene, and integration tests.

- [ ] **Step 7: Document ownership and recovery commands**

`docs/architecture/godot-foundation.md` must document module boundaries, the append-before-commit sequence, exact `LearningEventV1` fields, A/B content interfaces, A/C sync interface, profile file layout, quarantine behavior, route map, and standard test commands. `README.md` must include Godot 4.7.1 setup, the `/opt/homebrew/bin/godot` commands, offline slice launch instructions, and the fact that no live cloud credential is required.

- [ ] **Step 8: Commit the completed foundation**

```bash
git add project.godot README.md docs/architecture src/app/app_lifecycle.gd src/persistence/run_checkpoint_store.gd src/sync tests/unit/test_run_checkpoint_store.gd tests/unit/test_offline_sync_service.gd tests/integration
git commit -m "feat: complete recoverable offline game foundation"
```

## Final Verification

- [ ] Run `git status --short` and verify only intentional plan-execution changes are present.
- [ ] Run `/opt/homebrew/bin/godot --headless --path . --script res://tests/run_all.gd -- --suite all` and require exit `0` with no `FAIL` lines.
- [ ] Inspect `user://profiles.json` fixtures and assert no four-digit plaintext PIN is present.
- [ ] Inspect the event fixture against `LearningEventV1.validate`, then record its exact field/nullability list for the `packages/contracts/src/learning-event-v1.ts` mirror; Subproject A does not require the TypeScript package to exist.
- [ ] Confirm no game scene references `FileAccess`, `DirAccess`, HTTP/Supabase classes, or raw JSON parsing; only services under `src/persistence/`, `src/content/`, and `src/sync/` may do so.
- [ ] Confirm all registered routes instantiate offline, all long sequences expose Skip, and every icon action has a visible text label.
