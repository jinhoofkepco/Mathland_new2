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

class ProfileStoreFactory extends RefCounted:
	var base_path: String
	var stores := {}

	func _init(value: String) -> void:
		base_path = value

	func create_store(profile_id: String) -> AtomicJsonStore:
		if not stores.has(profile_id):
			stores[profile_id] = AtomicJsonStore.new("%s/%s" % [base_path, profile_id])
		return stores[profile_id]

class SharedStoreFactory extends RefCounted:
	var store: AtomicJsonStore

	func _init(base_path: String) -> void:
		store = AtomicJsonStore.new(base_path)

	func create_store(_profile_id: String) -> AtomicJsonStore:
		return store

class SamePathStoreFactory extends RefCounted:
	var base_path: String

	func _init(value: String) -> void:
		base_path = value

	func create_store(profile_id: String) -> AtomicJsonStore:
		if profile_id == "profile-a":
			return AtomicJsonStore.new(base_path)
		return AtomicJsonStore.new(
			"%s/alias/../%s" % [base_path.get_base_dir(), base_path.get_file()]
		)

class FaultInjectingProgressService extends ProgressService:
	var failure_point := ""

	func _rename_snapshot_path(from_path: String, to_path: String) -> Error:
		if failure_point == "quarantine_stage" and to_path.ends_with(".corrupt.tmp"):
			return ERR_CANT_CREATE
		if failure_point == "quarantine_rotation" and to_path.ends_with(".corrupt.bak"):
			return ERR_CANT_CREATE
		if failure_point in ["quarantine_promotion", "quarantine_restoration"] and from_path.ends_with(".corrupt.tmp") and to_path.ends_with(".corrupt"):
			return ERR_CANT_CREATE
		if failure_point == "quarantine_restoration" and from_path.ends_with(".corrupt.bak") and to_path.ends_with(".corrupt"):
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(
			ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)
		)

	func _remove_snapshot_path(path: String) -> Error:
		if failure_point == "quarantine_cleanup" and path.ends_with(".corrupt.bak"):
			return ERR_CANT_CREATE
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run(_tree: SceneTree) -> void:
	_cleanup()
	_test_corrupt_snapshot_is_quarantined_and_journal_replayed()
	_cleanup()
	_test_valid_snapshot_replays_only_later_events()
	_cleanup()
	_test_compacted_journal_reopens_from_durable_snapshot()
	_cleanup()
	_test_semantically_invalid_snapshots_are_quarantined()
	_cleanup()
	_test_replay_errors_scope_mismatches_gaps_and_out_of_order_propagate()
	_cleanup()
	_test_commit_requires_the_exact_next_already_journaled_event()
	_cleanup()
	_test_save_failure_rolls_back_without_signal()
	_cleanup()
	_test_load_recovery_must_persist_before_success()
	_cleanup()
	_test_successful_commit_persists_then_signals_and_snapshot_is_a_copy()
	_cleanup()
	_test_profile_store_factory_isolates_a_b_a_switches()
	_cleanup()
	_test_failed_profile_switch_clears_loaded_state()
	_cleanup()
	_test_factory_store_collisions_are_rejected_before_io()
	_cleanup()
	_test_direct_store_is_bound_to_one_profile()
	_cleanup()
	_test_default_store_uses_profile_directory()
	_cleanup()
	_test_snapshot_ahead_is_rejected_without_exposing_state()
	_cleanup()
	_test_semantic_quarantine_failures_preserve_both_artifacts_and_retry()
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
	var recovered_snapshot: Dictionary = store.load(SNAPSHOT_FILE)
	assert_true(recovered_snapshot.ok, "replayed progress was not made durable")
	if recovered_snapshot.get("ok", false):
		assert_eq(recovered_snapshot.value.last_sequence, 4)
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

func _test_compacted_journal_reopens_from_durable_snapshot() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var journal := _journal("compacted-events.jsonl")
	var first: Dictionary = journal.append(_answer_payload(true, 2, 24)).event
	var second: Dictionary = journal.append(_answer_payload(true, 2, 25)).event
	var third: Dictionary = journal.append(_answer_payload(false, 0, 26)).event
	var checkpoint := ProgressReducer.initial_state(PROFILE_ID)
	checkpoint = ProgressReducer.apply(checkpoint, first)
	checkpoint = ProgressReducer.apply(checkpoint, second)
	assert_eq(store.save(SNAPSHOT_FILE, checkpoint), OK)
	assert_eq(journal.compact_through(2), OK)

	var service := ProgressService.new(store)
	var loaded: Dictionary = service.load_profile(PROFILE_ID, journal)
	assert_true(loaded.ok, "compacted suffix could not reopen from its durable snapshot: %s" % loaded)
	if loaded.get("ok", false):
		assert_eq(service.snapshot().last_sequence, third.sequence)
		assert_eq(service.snapshot().activity_progress.foundation_ten_rods.attempts, 3)
	service.free()
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(_snapshot_path())), OK)
	var missing_snapshot_service := ProgressService.new(store)
	var missing_snapshot: Dictionary = missing_snapshot_service.load_profile(PROFILE_ID, journal)
	assert_eq(missing_snapshot.get("error"), "snapshot_behind_compaction")
	missing_snapshot_service.free()

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

func _test_load_recovery_must_persist_before_success() -> void:
	var store := ToggleSaveStore.new(BASE_PATH)
	var journal := _journal("load-save-failure.jsonl")
	assert_true(journal.append(_answer_payload(true, 2, 62)).ok)
	store.fail_saves = true
	var service := ProgressService.new(store)
	var loaded: Dictionary = service.load_profile(PROFILE_ID, journal)
	assert_eq(loaded.get("error"), "snapshot_recovery_save_failed")
	assert_eq(service.snapshot(), {}, "volatile replay state escaped after persistence failure")
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

func _test_profile_store_factory_isolates_a_b_a_switches() -> void:
	var factory := ProfileStoreFactory.new("%s/profiles" % BASE_PATH)
	var service := ProgressService.new(factory)
	var journal_a := _journal_for("profile-a", "profile-a-events.jsonl")
	assert_true(service.load_profile("profile-a", journal_a).ok)
	var event_a: Dictionary = journal_a.append(_answer_payload(true, 2, 81)).event
	assert_eq(service.commit(event_a), OK)

	var journal_b := _journal_for("profile-b", "profile-b-events.jsonl")
	assert_true(service.load_profile("profile-b", journal_b).ok)
	var event_b: Dictionary = journal_b.append(_answer_payload(true, 3, 82)).event
	assert_eq(service.commit(event_b), OK)

	var persisted_a: Dictionary = factory.stores["profile-a"].load(SNAPSHOT_FILE)
	var persisted_b: Dictionary = factory.stores["profile-b"].load(SNAPSHOT_FILE)
	assert_true(persisted_a.ok and persisted_b.ok)
	if persisted_a.get("ok", false) and persisted_b.get("ok", false):
		assert_eq(persisted_a.value.profile_id, "profile-a")
		assert_eq(persisted_a.value.apples, 2)
		assert_eq(persisted_b.value.profile_id, "profile-b")
		assert_eq(persisted_b.value.apples, 3)

	var reloaded_a := service.load_profile("profile-a", journal_a)
	assert_true(reloaded_a.ok)
	assert_eq(service.snapshot().profile_id, "profile-a")
	assert_eq(service.snapshot().apples, 2)
	assert_false(FileAccess.file_exists("%s.corrupt" % _profile_snapshot_path("profile-a")))
	assert_false(FileAccess.file_exists("%s.corrupt" % _profile_snapshot_path("profile-b")))
	service.free()

func _test_failed_profile_switch_clears_loaded_state() -> void:
	var factory := ProfileStoreFactory.new("%s/profiles" % BASE_PATH)
	var service := ProgressService.new(factory)
	var journal_a := _journal_for("profile-a", "failed-switch-a-events.jsonl")
	assert_true(service.load_profile("profile-a", journal_a).ok)
	var event_a: Dictionary = journal_a.append(_answer_payload(true, 2, 83)).event
	assert_eq(service.commit(event_a), OK)

	var failing_journal := StubJournal.new()
	failing_journal.replay_result = {"ok": false, "error": "journal_read_failed"}
	var failed := service.load_profile("profile-b", failing_journal)
	assert_false(failed.ok)
	assert_eq(failed.error, "journal_read_failed")
	assert_eq(service.snapshot(), {}, "a failed switch must not expose profile A state")
	assert_eq(service.commit(event_a), ERR_UNCONFIGURED)
	assert_true(factory.stores["profile-a"].load(SNAPSHOT_FILE).get("ok", false))
	assert_false(factory.stores["profile-b"].load(SNAPSHOT_FILE).get("ok", false))
	service.free()

func _test_factory_store_collisions_are_rejected_before_io() -> void:
	var cases := [
		{"name": "same-instance", "factory": SharedStoreFactory.new("%s/collision-same-instance" % BASE_PATH)},
		{"name": "same-path", "factory": SamePathStoreFactory.new("%s/collision-same-path" % BASE_PATH)},
	]
	for case in cases:
		var snapshot_path := "%s/collision-%s/%s" % [BASE_PATH, case.name, SNAPSHOT_FILE]
		var service := ProgressService.new(case.factory)
		var journal_a := _journal_for("profile-a", "collision-%s-a-events.jsonl" % case.name)
		assert_true(service.load_profile("profile-a", journal_a).ok)
		var event_a: Dictionary = journal_a.append(_answer_payload(true, 2, 85)).event
		assert_eq(service.commit(event_a), OK)
		var profile_a_bytes := _read_bytes(snapshot_path)

		var journal_b := _journal_for("profile-b", "collision-%s-b-events.jsonl" % case.name)
		var rejected := service.load_profile("profile-b", journal_b)
		assert_false(rejected.ok, "%s factory reused profile A storage" % case.name)
		assert_eq(rejected.get("error", ""), "store_profile_mismatch")
		assert_eq(service.snapshot(), {})
		assert_eq(_read_bytes(snapshot_path), profile_a_bytes, "%s touched profile A bytes" % case.name)
		assert_false(FileAccess.file_exists("%s.corrupt" % snapshot_path))
		service.free()
		_remove_snapshot_artifacts(snapshot_path)

func _test_direct_store_is_bound_to_one_profile() -> void:
	var snapshot_path := "%s/collision-direct/%s" % [BASE_PATH, SNAPSHOT_FILE]
	var store := AtomicJsonStore.new("%s/collision-direct" % BASE_PATH)
	var service := ProgressService.new(store)
	var journal_a := _journal_for("profile-a", "collision-direct-a-events.jsonl")
	assert_true(service.load_profile("profile-a", journal_a).ok)
	var event_a: Dictionary = journal_a.append(_answer_payload(true, 2, 86)).event
	assert_eq(service.commit(event_a), OK)
	var profile_a_bytes := _read_bytes(snapshot_path)

	var rejected := service.load_profile(
		"profile-b", _journal_for("profile-b", "collision-direct-b-events.jsonl")
	)
	assert_false(rejected.ok)
	assert_eq(rejected.get("error", ""), "store_profile_mismatch")
	assert_eq(service.snapshot(), {})
	assert_eq(_read_bytes(snapshot_path), profile_a_bytes)
	assert_false(FileAccess.file_exists("%s.corrupt" % snapshot_path))
	service.free()
	_remove_snapshot_artifacts(snapshot_path)

func _test_default_store_uses_profile_directory() -> void:
	var profile_id := "test-progress-default-profile"
	var snapshot_path := "user://profiles/%s/%s" % [profile_id, SNAPSHOT_FILE]
	_remove_snapshot_artifacts(snapshot_path)
	var service := ProgressService.new()
	var journal := _journal_for(profile_id, "default-store-events.jsonl")
	assert_true(service.load_profile(profile_id, journal).ok)
	var event: Dictionary = journal.append(_answer_payload(true, 2, 87)).event
	assert_eq(service.commit(event), OK)
	var persisted := AtomicJsonStore.new("user://profiles/%s" % profile_id).load(SNAPSHOT_FILE)
	assert_true(persisted.ok)
	if persisted.get("ok", false):
		assert_eq(persisted.value.profile_id, profile_id)
	service.free()
	_remove_snapshot_artifacts(snapshot_path)

func _test_snapshot_ahead_is_rejected_without_exposing_state() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var checkpoint := ProgressReducer.apply(
		ProgressReducer.initial_state(PROFILE_ID), _event(1, _answer_payload(true, 2, 84))
	)
	assert_eq(store.save(SNAPSHOT_FILE, checkpoint), OK)
	var service := ProgressService.new(store)
	var result := service.load_profile(PROFILE_ID, _journal("snapshot-ahead-events.jsonl"))
	assert_false(result.ok)
	assert_eq(result.error, "snapshot_ahead")
	assert_eq(service.snapshot(), {})
	assert_true(store.load(SNAPSHOT_FILE).get("ok", false), "a valid ahead snapshot must remain intact")
	assert_false(FileAccess.file_exists("%s.corrupt" % _snapshot_path()))
	service.free()

func _test_semantic_quarantine_failures_preserve_both_artifacts_and_retry() -> void:
	var expected_locations := {
		"quarantine_stage": {"new": [""], "old": [".corrupt"]},
		"quarantine_rotation": {"new": [".corrupt.tmp"], "old": [".corrupt"]},
		"quarantine_promotion": {"new": [".corrupt.tmp"], "old": [".corrupt"]},
		"quarantine_restoration": {"new": [".corrupt.tmp"], "old": [".corrupt.bak"]},
		"quarantine_cleanup": {"new": [".corrupt"], "old": [".corrupt.bak"]},
	}
	for failure_point in expected_locations:
		var store := AtomicJsonStore.new(BASE_PATH)
		var invalid_snapshot := ProgressReducer.initial_state(PROFILE_ID)
		invalid_snapshot.apples = -1
		assert_eq(store.save(SNAPSHOT_FILE, invalid_snapshot), OK)
		var new_bytes := _read_bytes(_snapshot_path())
		var old_bytes := ("old-corrupt-%s" % failure_point).to_utf8_buffer()
		_write_bytes("%s.corrupt" % _snapshot_path(), old_bytes)
		var journal := _journal("%s-events.jsonl" % failure_point)
		var service := FaultInjectingProgressService.new(store)
		service.failure_point = failure_point

		var failed := service.load_profile(PROFILE_ID, journal)
		assert_false(failed.ok, "%s unexpectedly quarantined" % failure_point)
		assert_eq(failed.get("error", ""), "quarantine_failed")
		assert_eq(service.snapshot(), {}, "%s exposed stale state" % failure_point)
		assert_eq(
			_paths_containing(_snapshot_path(), new_bytes),
			expected_locations[failure_point].new,
			"%s lost or duplicated the invalid snapshot" % failure_point,
		)
		assert_eq(
			_paths_containing(_snapshot_path(), old_bytes),
			expected_locations[failure_point].old,
			"%s lost or duplicated the prior corrupt artifact" % failure_point,
		)

		service.failure_point = ""
		var recovered := service.load_profile(PROFILE_ID, journal)
		assert_true(recovered.ok, "%s did not recover on retry" % failure_point)
		assert_eq(_paths_containing(_snapshot_path(), new_bytes), [".corrupt"])
		assert_eq(_paths_containing(_snapshot_path(), old_bytes), [])
		assert_false(FileAccess.file_exists("%s.corrupt.tmp" % _snapshot_path()))
		assert_false(FileAccess.file_exists("%s.corrupt.bak" % _snapshot_path()))
		service.free()
		_cleanup_snapshot_files()

func _journal(name: String) -> EventJournal:
	return _journal_for(PROFILE_ID, name)

func _journal_for(profile_id: String, name: String) -> EventJournal:
	var journal := EventJournal.new()
	var configured := journal.configure(profile_id, DEVICE_ID, "%s/%s" % [BASE_PATH, name])
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

func _profile_snapshot_path(profile_id: String) -> String:
	return "%s/profiles/%s/%s" % [BASE_PATH, profile_id, SNAPSHOT_FILE]

func _write_text(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _paths_containing(base_path: String, expected: PackedByteArray) -> Array:
	var result := []
	for suffix in ["", ".corrupt", ".corrupt.tmp", ".corrupt.bak"]:
		var path := "%s%s" % [base_path, suffix]
		if FileAccess.file_exists(path) and _read_bytes(path) == expected:
			result.append(suffix)
	return result

func _cleanup_snapshot_files() -> void:
	_remove_snapshot_artifacts(_snapshot_path())

func _remove_snapshot_artifacts(snapshot_path: String) -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt", ".corrupt.tmp", ".corrupt.bak"]:
		var path := "%s%s" % [snapshot_path, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _cleanup() -> void:
	_cleanup_snapshot_files()
	for profile_id in ["profile-a", "profile-b"]:
		for suffix in ["", ".tmp", ".bak", ".corrupt", ".corrupt.tmp", ".corrupt.bak"]:
			var snapshot_path := "%s%s" % [_profile_snapshot_path(profile_id), suffix]
			if FileAccess.file_exists(snapshot_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(snapshot_path))
	_remove_snapshot_artifacts("%s/collision-same-instance/%s" % [BASE_PATH, SNAPSHOT_FILE])
	_remove_snapshot_artifacts("%s/collision-same-path/%s" % [BASE_PATH, SNAPSHOT_FILE])
	_remove_snapshot_artifacts("%s/collision-direct/%s" % [BASE_PATH, SNAPSHOT_FILE])
	_remove_snapshot_artifacts("user://profiles/test-progress-default-profile/%s" % SNAPSHOT_FILE)
	for journal_name in ["corrupt-events.jsonl", "later-events.jsonl", "compacted-events.jsonl", "semantic-events.jsonl", "commit-guard.jsonl", "save-failure.jsonl", "load-save-failure.jsonl", "successful-commit.jsonl", "profile-a-events.jsonl", "profile-b-events.jsonl", "failed-switch-a-events.jsonl", "snapshot-ahead-events.jsonl", "default-store-events.jsonl", "collision-same-instance-a-events.jsonl", "collision-same-instance-b-events.jsonl", "collision-same-path-a-events.jsonl", "collision-same-path-b-events.jsonl", "collision-direct-a-events.jsonl", "collision-direct-b-events.jsonl", "quarantine_stage-events.jsonl", "quarantine_rotation-events.jsonl", "quarantine_promotion-events.jsonl", "quarantine_restoration-events.jsonl", "quarantine_cleanup-events.jsonl"]:
		for suffix in ["", ".partial.corrupt", ".partial.corrupt.tmp", ".recovery.tmp", ".recovery.bak", ".compaction.cursor.json", ".compaction.cursor.json.tmp", ".compaction.cursor.json.bak", ".compact.tmp", ".compact.bak"]:
			var path := "%s/%s%s" % [BASE_PATH, journal_name, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
