extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/run_checkpoint_store"
const PROFILE_ID := "11111111-1111-4111-8111-111111111111"
const OTHER_PROFILE_ID := "22222222-2222-4222-8222-222222222222"
const SESSION_ID := "33333333-3333-4333-8333-333333333333"
const STORE_PATH := "res://src/persistence/run_checkpoint_store.gd"

func run(_tree: SceneTree) -> void:
	_cleanup()
	assert_true(ResourceLoader.exists(STORE_PATH), "missing RunCheckpointStore class")
	if not ResourceLoader.exists(STORE_PATH):
		return
	var StoreScript: Variant = load(STORE_PATH)
	var store: Variant = StoreScript.new(BASE_PATH)
	_test_atomic_round_trip(store)
	_test_profile_scope_and_schema_validation(store)
	_test_malformed_and_semantic_values_are_quarantined(store)
	_test_oversized_backup_is_rejected_before_recovery(store)
	_test_delete_removes_only_the_requested_profile(store)
	_cleanup()

func _test_atomic_round_trip(store: Variant) -> void:
	var checkpoint := _checkpoint(PROFILE_ID)
	var saved: Dictionary = store.save(checkpoint)
	assert_true(saved.ok)
	assert_false(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json.tmp")))
	assert_false(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json.bak")))
	checkpoint.run_state.health = 0
	var loaded: Dictionary = store.load(PROFILE_ID, "a-vertical-1")
	assert_true(loaded.ok)
	assert_eq(loaded.checkpoint, _checkpoint(PROFILE_ID), "checkpoint storage must deep-copy its input")
	loaded.checkpoint.run_state.health = 0
	assert_eq(store.load(PROFILE_ID, "a-vertical-1").checkpoint.run_state.health, 3)

func _test_profile_scope_and_schema_validation(store: Variant) -> void:
	assert_eq(store.load(OTHER_PROFILE_ID, "a-vertical-1").error, "not_found")
	assert_eq(store.load("../escape", "a-vertical-1").error, "invalid_profile_id")
	assert_true(store.save(_checkpoint(OTHER_PROFILE_ID, "44444444-4444-4444-8444-444444444444")).ok)
	assert_true(store.load(PROFILE_ID, "a-vertical-1").ok, "saving another profile overwrote the active profile")
	assert_true(store.load(OTHER_PROFILE_ID, "a-vertical-1").ok, "profile-scoped checkpoint was written to the wrong path")
	var unknown_field := _checkpoint(PROFILE_ID)
	unknown_field["unexpected"] = true
	assert_eq(store.save(unknown_field).error, "invalid_checkpoint")
	var missing_run_start := _checkpoint(PROFILE_ID)
	missing_run_start.last_event_sequence = 0
	assert_eq(store.save(missing_run_start).get("error", ""), "invalid_checkpoint")
	var mismatched_question := _checkpoint(PROFILE_ID)
	mismatched_question.current_question.content_version = "other-version"
	assert_eq(store.save(mismatched_question).error, "invalid_checkpoint")
	var wrong_content: Dictionary = store.load(PROFILE_ID, "other-version")
	assert_false(wrong_content.ok)
	assert_eq(wrong_content.error, "content_version_mismatch")
	assert_true(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json")), "temporary content mismatch must retain the checkpoint")

func _test_malformed_and_semantic_values_are_quarantined(store: Variant) -> void:
	assert_true(_write_text(_path(PROFILE_ID, "run_checkpoint.json"), "{broken"))
	var malformed: Dictionary = store.load(PROFILE_ID, "a-vertical-1")
	assert_false(malformed.ok)
	assert_eq(malformed.error, "invalid_json")
	assert_true(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json.corrupt")))
	var invalid := _checkpoint(PROFILE_ID)
	invalid.last_event_sequence = -1
	assert_true(_write_text(_path(PROFILE_ID, "run_checkpoint.json"), JSON.stringify(invalid)))
	var semantic: Dictionary = store.load(PROFILE_ID, "a-vertical-1")
	assert_false(semantic.ok)
	assert_eq(semantic.error, "invalid_checkpoint")
	assert_true(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json.corrupt")))
	assert_false(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json")))

func _test_delete_removes_only_the_requested_profile(store: Variant) -> void:
	assert_true(store.save(_checkpoint(PROFILE_ID)).ok)
	assert_true(store.save(_checkpoint(OTHER_PROFILE_ID, "44444444-4444-4444-8444-444444444444")).ok)
	assert_true(store.delete(PROFILE_ID).ok)
	assert_eq(store.load(PROFILE_ID, "a-vertical-1").error, "not_found")
	assert_true(store.load(OTHER_PROFILE_ID, "a-vertical-1").ok)
	assert_true(store.delete(PROFILE_ID).ok, "checkpoint deletion must be idempotent")

func _test_oversized_backup_is_rejected_before_recovery(store: Variant) -> void:
	assert_true(store.delete(PROFILE_ID).ok)
	var backup_path := _path(PROFILE_ID, "run_checkpoint.json.bak")
	assert_true(_write_text(backup_path, "x".repeat(1_048_577)))
	var loaded: Dictionary = store.load(PROFILE_ID, "a-vertical-1")
	assert_false(loaded.ok)
	assert_eq(loaded.error, "invalid_checkpoint")
	assert_false(FileAccess.file_exists(backup_path))
	assert_false(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json")))
	assert_true(FileAccess.file_exists(_path(PROFILE_ID, "run_checkpoint.json.corrupt")))

func _checkpoint(profile_id: String, session_id: String = SESSION_ID) -> Dictionary:
	var question := {
		"question_id": "foundation_ten_rods:a-vertical-1:count_to_10:43",
		"activity_id": "foundation_ten_rods",
		"content_version": "a-vertical-1",
		"generator_id": "foundation_ten_rods",
		"band_id": "count_to_10",
		"seed": 43,
		"resolved_parameters": {"left": 1, "right": 3},
		"prompt_key": "activity.foundation_ten_rods.add",
		"correct_answer": 4,
		"answer_layout": "numeric_keypad",
		"manipulative": {"kind": "ten_rods", "scene_path": "res://scenes/game/manipulatives/ten_rod_board.tscn"},
	}
	return {
		"schema_version": 1,
		"profile_id": profile_id,
		"session_id": session_id,
		"content_version": "a-vertical-1",
		"activity_id": "foundation_ten_rods",
		"run_state": {
			"revision": 4,
			"session_id": session_id,
			"activity_id": "foundation_ten_rods",
			"content_version": "a-vertical-1",
			"stage_id": "count_to_10",
			"health": 3,
			"score": 1,
			"combo": 1,
			"question_index": 1,
			"current_question": question.duplicate(true),
			"current_seed": 43,
			"awaiting_answer": true,
			"boss_state": false,
			"earned_rewards": {"apples": 2},
			"paused": false,
			"timer_enabled": false,
			"timer_started_at_ms": 0,
			"timer_remaining_ms": 0,
			"completion_reason": "",
			"status": "running",
		},
		"current_question": question,
		"last_event_sequence": 2,
	}

func _write_text(path: String, value: String) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

func _path(profile_id: String, file_name: String) -> String:
	return "%s/%s/%s" % [BASE_PATH, profile_id, file_name]

func _cleanup() -> void:
	_remove_tree(BASE_PATH)

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
