extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/progress"
const PROFILE_ID := "profile-a"
const DEVICE_ID := "device-a"
const SNAPSHOT_FILE := "snapshot.json"
const AtomicJsonStore = preload("res://src/persistence/atomic_json_store.gd")
const EventJournal = preload("res://src/persistence/event_journal.gd")
const LearningEventV1 = preload("res://src/events/learning_event_v1.gd")
const ProgressReducer = preload("res://src/progress/progress_reducer.gd")
const ProgressService = preload("res://src/progress/progress_service.gd")

class StubJournal extends EventJournal:
	var replay_result: Dictionary = {"ok": true, "events": [], "quarantined_tail": false}

	func replay() -> Dictionary:
		return replay_result.duplicate(true)

class ToggleSaveStore extends AtomicJsonStore:
	var fail_saves := false

	func save(path: String, value: Variant) -> Error:
		if fail_saves:
			return ERR_CANT_CREATE
		return super(path, value)

func run(_tree: SceneTree) -> void:
	_cleanup()
	_test_corrupt_snapshot_is_quarantined_and_journal_replayed()
	_cleanup()
	_test_valid_snapshot_replays_only_later_events()
	_cleanup()
	_test_semantically_invalid_snapshots_are_quarantined()
	_cleanup()
	_test_replay_errors_scope_mismatches_gaps_and_out_of_order_propagate()
	_cleanup()
	_test_commit_requires_the_exact_next_already_journaled_event()
	_cleanup()
	_test_save_failure_rolls_back_without_signal()
	_cleanup()
	_test_successful_commit_persists_then_signals_and_snapshot_is_a_copy()
	_cleanup()

func _test_corrupt_snapshot_is_quarantined_and_journal_replayed() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	_write_text(_snapshot_path(), "{broken")
	var journal := _journal("corrupt-events.jsonl")
	assert_true(journal.append(_answer_payload(true, 2, 11)).ok)
	assert_true(journal.append(_answer_payload(true, 2, 12)).ok)
	assert_true(journal.append(_answer_payload(false, 0, 13)).ok)
	assert_true(journal.append(_run_completed_payload("health_depleted", 0, 4)).ok)

	var service := ProgressService.new(store)
	var loaded := service.load_profile(PROFILE_ID, journal)
	assert_true(loaded.ok)
	assert_true(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	var state := service.snapshot()
	assert_eq(state.last_sequence, 4)
	assert_eq(state.apples, 4)
	assert_eq(state.activity_progress.foundation_ten_rods.attempts, 3)
	assert_eq(state.activity_progress.foundation_ten_rods.correct, 2)
	assert_eq(state.pending_review, 1)
	assert_eq(state.run_totals.health_depleted, 1)
	service.free()

func _test_valid_snapshot_replays_only_later_events() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var journal := _journal("later-events.jsonl")
	var first: Dictionary = journal.append(_answer_payload(true, 2, 21)).event
	var second: Dictionary = journal.append(_answer_payload(true, 2, 22)).event
	var third: Dictionary = journal.append(_answer_payload(false, 0, 23)).event
	var checkpoint := ProgressReducer.initial_state(PROFILE_ID)
	checkpoint = ProgressReducer.apply(checkpoint, first)
	checkpoint = ProgressReducer.apply(checkpoint, second)
	assert_eq(store.save(SNAPSHOT_FILE, checkpoint), OK)

	var service := ProgressService.new(store)
	var loaded := service.load_profile(PROFILE_ID, journal)
	assert_true(loaded.ok)
	var state := service.snapshot()
	assert_eq(state.last_sequence, third.sequence)
	assert_eq(state.apples, 4, "events at or below the checkpoint must not replay")
	assert_eq(state.activity_progress.foundation_ten_rods.attempts, 3)
	assert_eq(state.pending_review, 1)
	service.free()

func _test_semantically_invalid_snapshots_are_quarantined() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var journal := _journal("semantic-events.jsonl")
	assert_true(journal.append(_answer_payload(true, 2, 31)).ok)
	var invalid_value := ProgressReducer.initial_state(PROFILE_ID)
	invalid_value.apples = -1
	assert_eq(store.save(SNAPSHOT_FILE, invalid_value), OK)
	var service := ProgressService.new(store)
	assert_true(service.load_profile(PROFILE_ID, journal).ok)
	assert_eq(service.snapshot().apples, 2)
	assert_true(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	service.free()

	_cleanup_snapshot_files()
	var unknown_key := ProgressReducer.initial_state(PROFILE_ID)
	unknown_key["unexpected"] = true
	assert_eq(store.save(SNAPSHOT_FILE, unknown_key), OK)
	var unknown_service := ProgressService.new(store)
	assert_true(unknown_service.load_profile(PROFILE_ID, journal).ok)
	assert_eq(unknown_service.snapshot().apples, 2)
	assert_true(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	unknown_service.free()

	_cleanup_snapshot_files()
	var foreign_scope := ProgressReducer.initial_state("profile-b")
	assert_eq(store.save(SNAPSHOT_FILE, foreign_scope), OK)
	var foreign_service := ProgressService.new(store)
	assert_true(foreign_service.load_profile(PROFILE_ID, journal).ok)
	assert_eq(foreign_service.snapshot().profile_id, PROFILE_ID)
	assert_true(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	foreign_service.free()

	_cleanup_snapshot_files()
	var duplicate_apples := ProgressReducer.initial_state(PROFILE_ID)
	duplicate_apples.inventory.apples = 1
	assert_eq(store.save(SNAPSHOT_FILE, duplicate_apples), OK)
	var duplicate_apples_service := ProgressService.new(store)
	assert_true(duplicate_apples_service.load_profile(PROFILE_ID, journal).ok)
	assert_eq(duplicate_apples_service.snapshot().inventory, {})
	assert_true(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	duplicate_apples_service.free()

func _test_replay_errors_scope_mismatches_gaps_and_out_of_order_propagate() -> void:
	var missing_error := StubJournal.new()
	missing_error.replay_result = {"ok": false}
	var missing_error_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var malformed_failure := missing_error_service.load_profile(PROFILE_ID, missing_error)
	assert_false(malformed_failure.ok)
	assert_eq(malformed_failure.error, "invalid_replay_result")
	missing_error_service.free()

	var non_boolean_ok := StubJournal.new()
	non_boolean_ok.replay_result = {"ok": "yes", "events": []}
	var non_boolean_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var non_boolean_result := non_boolean_service.load_profile(PROFILE_ID, non_boolean_ok)
	assert_false(non_boolean_result.ok)
	assert_eq(non_boolean_result.error, "invalid_replay_result")
	non_boolean_service.free()

	var replay_error := StubJournal.new()
	replay_error.replay_result = {"ok": false, "error": "invalid_record", "line": 2}
	var failed_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var failed := failed_service.load_profile(PROFILE_ID, replay_error)
	assert_false(failed.ok)
	assert_eq(failed.error, "invalid_record")
	assert_eq(failed.get("line", 0), 2)
	assert_eq(failed_service.snapshot(), {}, "a replay error must not become an empty successful state")
	failed_service.free()

	var foreign_event := _event(1, _answer_payload(true, 2, 41), "profile-b")
	var wrong_scope := StubJournal.new()
	wrong_scope.replay_result = {"ok": true, "events": [foreign_event], "quarantined_tail": false}
	var wrong_scope_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var scope_result := wrong_scope_service.load_profile(PROFILE_ID, wrong_scope)
	assert_false(scope_result.ok)
	assert_eq(scope_result.error, "scope_mismatch")
	assert_eq(wrong_scope_service.snapshot(), {})
	wrong_scope_service.free()

	var first := _event(1, _answer_payload(true, 2, 42))
	var third := _event(3, _answer_payload(true, 2, 43))
	var gap := StubJournal.new()
	gap.replay_result = {"ok": true, "events": [first, third], "quarantined_tail": false}
	var gap_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var gap_result := gap_service.load_profile(PROFILE_ID, gap)
	assert_false(gap_result.ok)
	assert_eq(gap_result.error, "invalid_sequence")
	assert_eq(gap_service.snapshot(), {})
	gap_service.free()

	var second := _event(2, _answer_payload(true, 2, 44))
	var out_of_order := StubJournal.new()
	out_of_order.replay_result = {"ok": true, "events": [first, second, first], "quarantined_tail": false}
	var order_service := ProgressService.new(AtomicJsonStore.new(BASE_PATH))
	var order_result := order_service.load_profile(PROFILE_ID, out_of_order)
	assert_false(order_result.ok)
	assert_eq(order_result.error, "invalid_sequence")
	assert_eq(order_service.snapshot(), {})
	order_service.free()

func _test_commit_requires_the_exact_next_already_journaled_event() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var journal := _journal("commit-guard.jsonl")
	var service := ProgressService.new(store)
	assert_true(service.load_profile(PROFILE_ID, journal).ok)
	var unjournaled := _event(1, _answer_payload(true, 2, 51))
	assert_eq(service.commit(unjournaled), ERR_DOES_NOT_EXIST)
	assert_eq(service.snapshot().last_sequence, 0)

	var journaled: Dictionary = journal.append(_answer_payload(true, 2, 52)).event
	var different := journaled.duplicate(true)
	different.reward_delta.apples = 3
	assert_true(LearningEventV1.validate(different).is_empty())
	assert_eq(service.commit(different), ERR_INVALID_DATA)
	assert_eq(service.snapshot().last_sequence, 0)

	var foreign := journaled.duplicate(true)
	foreign.profile_id = "profile-b"
	assert_true(LearningEventV1.validate(foreign).is_empty())
	assert_eq(service.commit(foreign), ERR_INVALID_PARAMETER)
	assert_eq(service.commit(journaled), OK)
	assert_eq(service.commit(journaled), ERR_ALREADY_EXISTS)
	service.free()

func _test_save_failure_rolls_back_without_signal() -> void:
	var store := ToggleSaveStore.new(BASE_PATH)
	var journal := _journal("save-failure.jsonl")
	var service := ProgressService.new(store)
	assert_true(service.load_profile(PROFILE_ID, journal).ok)
	var signal_states: Array[Dictionary] = []
	service.progress_changed.connect(func(state: Dictionary): signal_states.append(state))
	var event: Dictionary = journal.append(_answer_payload(true, 2, 61)).event
	store.fail_saves = true
	assert_eq(service.commit(event), ERR_CANT_CREATE)
	assert_eq(service.snapshot(), ProgressReducer.initial_state(PROFILE_ID))
	assert_eq(signal_states.size(), 0)
	assert_false(FileAccess.file_exists(_snapshot_path()))
	service.free()

func _test_successful_commit_persists_then_signals_and_snapshot_is_a_copy() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var journal := _journal("successful-commit.jsonl")
	var service := ProgressService.new(store)
	assert_true(service.load_profile(PROFILE_ID, journal).ok)
	var signal_states: Array[Dictionary] = []
	var persisted_at_signal: Array[bool] = []
	service.progress_changed.connect(
		func(state: Dictionary):
			signal_states.append(state)
			persisted_at_signal.append(store.load(SNAPSHOT_FILE).get("ok", false))
	)
	var event: Dictionary = journal.append(_answer_payload(true, 2, 71)).event
	assert_eq(service.commit(event), OK)
	assert_eq(signal_states.size(), 1)
	assert_eq(persisted_at_signal, [true])
	var persisted := store.load(SNAPSHOT_FILE)
	assert_true(persisted.ok, "snapshot must exist before progress_changed is emitted")
	if persisted.get("ok", false):
		var normalized_signal: Variant = JSON.parse_string(JSON.stringify(signal_states[0]))
		assert_eq(JSON.stringify(persisted.value), JSON.stringify(normalized_signal))
	var exposed := service.snapshot()
	exposed.inventory["stars"] = 99
	exposed.activity_progress.foundation_ten_rods.attempts = 99
	assert_false(service.snapshot().inventory.has("stars"))
	assert_eq(service.snapshot().activity_progress.foundation_ten_rods.attempts, 1)
	signal_states[0].apples = 99
	assert_eq(service.snapshot().apples, 2, "signal payload must not alias service state")
	service.free()

func _journal(name: String) -> EventJournal:
	var journal := EventJournal.new()
	var configured := journal.configure(PROFILE_ID, DEVICE_ID, "%s/%s" % [BASE_PATH, name])
	assert_true(configured.ok, "journal configuration failed: %s" % configured)
	return journal

func _event(sequence: int, payload: Dictionary, profile_id: String = PROFILE_ID) -> Dictionary:
	return LearningEventV1.create(
		{"profile_id": profile_id, "device_id": DEVICE_ID, "sequence": sequence}, payload
	)

func _answer_payload(correctness: bool, apples: int, seed: int) -> Dictionary:
	return {
		"session_id": "session-a",
		"client_timestamp": "2026-07-21T09:00:00Z",
		"event_type": "answer_submitted",
		"activity_id": "foundation_ten_rods",
		"content_version": "a-vertical-1",
		"question_seed": seed,
		"generator_id": "foundation_ten_rods",
		"band_id": "count_to_10",
		"resolved_parameters": {"left": 3, "right": 4},
		"submitted_answer": 7 if correctness else 8,
		"correct_answer": 7,
		"correctness": correctness,
		"response_duration_ms": 1200,
		"hints": 0,
		"health_delta": 0 if correctness else -1,
		"combo": 1 if correctness else 0,
		"reward_delta": {"apples": apples},
	}

func _run_completed_payload(reason: String, final_health: int, apples: int) -> Dictionary:
	return {
		"session_id": "session-a",
		"client_timestamp": "2026-07-21T09:01:00Z",
		"event_type": "run_completed",
		"completion_reason": reason,
		"final_score": 2,
		"final_health": final_health,
		"earned_rewards": {"apples": apples},
	}

func _snapshot_path() -> String:
	return "%s/%s" % [BASE_PATH, SNAPSHOT_FILE]

func _write_text(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _cleanup_snapshot_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [_snapshot_path(), suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _cleanup() -> void:
	_cleanup_snapshot_files()
	for journal_name in ["corrupt-events.jsonl", "later-events.jsonl", "semantic-events.jsonl", "commit-guard.jsonl", "save-failure.jsonl", "successful-commit.jsonl"]:
		for suffix in ["", ".partial.corrupt", ".partial.corrupt.tmp", ".recovery.tmp", ".recovery.bak"]:
			var path := "%s/%s%s" % [BASE_PATH, journal_name, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
