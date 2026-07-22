class_name SyncCursorStore
extends RefCounted

const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const FILE_NAME := "cursor.json"
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_SERVER_CURSOR_LENGTH := 2048

var _profile_id := ""
var _device_id := ""
var _store: Variant

func _init(profile_id: String, device_id: String, base_path: String = "user://sync") -> void:
	_profile_id = profile_id
	_device_id = device_id
	_store = AtomicJsonStoreScript.new("%s/%s" % [base_path.rstrip("/"), profile_id])

func load_cursor() -> Dictionary:
	var loaded: Dictionary = _store.load(FILE_NAME)
	if not loaded.get("ok", false):
		if loaded.get("error") == "not_found":
			return {"acknowledged_sequence": 0, "server_cursor": ""}
		return {
			"acknowledged_sequence": 0,
			"server_cursor": "",
			"diagnostic": "invalid_sync_cursor",
			"storage_error": String(loaded.get("error", "load_failed")),
		}
	var value: Variant = loaded.get("value", {})
	if not _is_valid(value):
		return {"acknowledged_sequence": 0, "server_cursor": "", "diagnostic": "invalid_sync_cursor"}
	var cursor: Dictionary = value
	return {
		"acknowledged_sequence": int(cursor.acknowledged_sequence),
		"server_cursor": String(cursor.server_cursor),
	}

func save_cursor(sequence: int, server_cursor: String) -> Error:
	if sequence < 0 or sequence > MAX_SAFE_INTEGER or not _is_valid_server_cursor(server_cursor):
		return ERR_INVALID_PARAMETER
	return _store.save(FILE_NAME, {
		"schema_version": 1,
		"profile_id": _profile_id,
		"device_id": _device_id,
		"acknowledged_sequence": sequence,
		"server_cursor": server_cursor,
	})

func _is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var cursor: Dictionary = value
	return (
		cursor.size() == 5
		and cursor.get("schema_version") == 1
		and cursor.get("profile_id") == _profile_id
		and cursor.get("device_id") == _device_id
		and _is_nonnegative_safe_integer(cursor.get("acknowledged_sequence"))
		and _is_valid_server_cursor(cursor.get("server_cursor"))
	)

func _is_nonnegative_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0 and value <= MAX_SAFE_INTEGER
	return (
		value is float
		and is_finite(value)
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value == floor(value)
	)

func _is_valid_server_cursor(value: Variant) -> bool:
	if not value is String:
		return false
	var cursor: String = value
	if cursor.strip_edges().is_empty() or cursor.length() > MAX_SERVER_CURSOR_LENGTH:
		return false
	for index in cursor.length():
		if cursor.unicode_at(index) < 32:
			return false
	return true
