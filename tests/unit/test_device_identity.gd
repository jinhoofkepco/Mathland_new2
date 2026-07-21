extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/device_identity"
const AtomicJsonStore = preload("res://src/persistence/atomic_json_store.gd")
const DeviceIdentity = preload("res://src/persistence/device_identity.gd")
const UuidV4 = preload("res://src/core/uuid_v4.gd")

func run(_tree: SceneTree) -> void:
	_cleanup_files(["device.json", "device.json.tmp", "device.json.bak"])

	var store := AtomicJsonStore.new(BASE_PATH)
	var first := DeviceIdentity.new(store).load_or_create()
	var second := DeviceIdentity.new(store).load_or_create()
	assert_true(UuidV4.is_valid(first))
	assert_eq(second, first)

	_cleanup_files(["device.json", "device.json.tmp", "device.json.bak"])

func _cleanup_files(file_names: Array[String]) -> void:
	for file_name in file_names:
		var file_path := "%s/%s" % [BASE_PATH, file_name]
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
