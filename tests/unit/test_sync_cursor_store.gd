extends "res://tests/support/test_case.gd"

const SyncCursorStoreScript = preload("res://src/sync/sync_cursor_store.gd")
const BASE_PATH := "user://tests/sync_cursor_store"
const PROFILE_ID := "profile-1"
const DEVICE_ID := "device-1"

func run(_tree: SceneTree) -> void:
	_cleanup()
	var store := SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH)
	assert_eq(store.load_cursor(), {"acknowledged_sequence": 0, "server_cursor": ""})
	assert_eq(store.save_cursor(7, "7"), OK)
	assert_eq(
		SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).load_cursor(),
		{"acknowledged_sequence": 7, "server_cursor": "7"},
	)
	_test_fractional_sequence_is_rejected()
	_test_malformed_cursor_is_not_treated_as_an_empty_queue()
	_test_identity_and_cursor_fields_are_strict()
	_cleanup()

func _test_fractional_sequence_is_rejected() -> void:
	assert_true(_write_cursor({
		"schema_version": 1,
		"profile_id": PROFILE_ID,
		"device_id": DEVICE_ID,
		"acknowledged_sequence": 1.5,
		"server_cursor": "1",
	}))
	var loaded: Dictionary = SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).load_cursor()
	assert_eq(loaded.get("diagnostic"), "invalid_sync_cursor")

func _test_malformed_cursor_is_not_treated_as_an_empty_queue() -> void:
	assert_true(_write_text(_cursor_path(), "{broken"))
	var loaded: Dictionary = SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).load_cursor()
	assert_eq(loaded.get("diagnostic"), "invalid_sync_cursor")
	assert_eq(loaded.get("storage_error"), "invalid_json")
	assert_true(FileAccess.file_exists("%s.corrupt" % _cursor_path()))

func _test_identity_and_cursor_fields_are_strict() -> void:
	for invalid in [
		{"schema_version": 1, "profile_id": "other", "device_id": DEVICE_ID, "acknowledged_sequence": 1, "server_cursor": "1"},
		{"schema_version": 1, "profile_id": PROFILE_ID, "device_id": "other", "acknowledged_sequence": 1, "server_cursor": "1"},
		{"schema_version": 1, "profile_id": PROFILE_ID, "device_id": DEVICE_ID, "acknowledged_sequence": -1, "server_cursor": "1"},
		{"schema_version": 1, "profile_id": PROFILE_ID, "device_id": DEVICE_ID, "acknowledged_sequence": 1, "server_cursor": ""},
	]:
		assert_true(_write_cursor(invalid))
		assert_eq(
			SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).load_cursor().get("diagnostic"),
			"invalid_sync_cursor",
		)
	assert_eq(SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).save_cursor(-1, "1"), ERR_INVALID_PARAMETER)
	assert_eq(SyncCursorStoreScript.new(PROFILE_ID, DEVICE_ID, BASE_PATH).save_cursor(1, ""), ERR_INVALID_PARAMETER)

func _write_cursor(value: Dictionary) -> bool:
	return _write_text(_cursor_path(), JSON.stringify(value))

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

func _cursor_path() -> String:
	return "%s/%s/cursor.json" % [BASE_PATH, PROFILE_ID]

func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [_cursor_path(), suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
