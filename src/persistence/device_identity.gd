class_name DeviceIdentity
extends RefCounted

const FILE_NAME := "device.json"
const UUID_V4 = preload("res://src/core/uuid_v4.gd")

var _store: Variant

func _init(store: Variant) -> void:
	_store = store

func load_or_create() -> String:
	var loaded: Dictionary = _store.load(FILE_NAME)
	var value: Dictionary = loaded.get("value", {})
	if loaded.get("ok", false) and UUID_V4.is_valid(value.get("device_id", "")):
		return value.device_id
	var device_id := UUID_V4.generate()
	assert(_store.save(FILE_NAME, {"schema_version": 1, "device_id": device_id}) == OK)
	return device_id
