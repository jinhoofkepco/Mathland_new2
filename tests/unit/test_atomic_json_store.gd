extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/atomic"
const AtomicJsonStore = preload("res://src/persistence/atomic_json_store.gd")

func run(_tree: SceneTree) -> void:
	_cleanup_files(["profile.json", "profile.json.tmp", "profile.json.bak", "broken.json", "broken.json.corrupt", "blocked.json", "blocked.json.corrupt", "recovered.json", "recovered.json.bak", "recovered.json.tmp"])
	_cleanup_directory("blocked.json.corrupt")

	var store := AtomicJsonStore.new(BASE_PATH)
	assert_eq(store.save("profile.json", {"nickname": "모아"}), OK)
	assert_eq(store.load("profile.json"), {"ok": true, "value": {"nickname": "모아"}})
	assert_false(FileAccess.file_exists("%s/profile.json.tmp" % BASE_PATH))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE_PATH))
	var broken_file := FileAccess.open("%s/broken.json" % BASE_PATH, FileAccess.WRITE)
	broken_file.store_string("{broken")
	broken_file.close()
	var recovered := store.load("broken.json")
	assert_false(recovered.ok)
	assert_eq(recovered.error, "invalid_json")
	assert_true(recovered.quarantine_path.ends_with(".corrupt"))
	assert_true(FileAccess.file_exists(recovered.quarantine_path))

	var blocked_file := FileAccess.open("%s/blocked.json" % BASE_PATH, FileAccess.WRITE)
	blocked_file.store_string("{broken")
	blocked_file.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/blocked.json.corrupt" % BASE_PATH))
	var blocked_quarantine := store.load("blocked.json")
	assert_false(blocked_quarantine.ok)
	assert_eq(blocked_quarantine.error, "quarantine_failed")
	assert_true(FileAccess.file_exists("%s/blocked.json" % BASE_PATH))

	var interrupted_backup := FileAccess.open("%s/recovered.json.bak" % BASE_PATH, FileAccess.WRITE)
	interrupted_backup.store_string(JSON.stringify({"nickname": "backup"}))
	interrupted_backup.close()
	var interrupted_temporary := FileAccess.open("%s/recovered.json.tmp" % BASE_PATH, FileAccess.WRITE)
	interrupted_temporary.store_string(JSON.stringify({"nickname": "uncommitted"}))
	interrupted_temporary.close()
	assert_eq(store.load("recovered.json"), {"ok": true, "value": {"nickname": "backup"}})
	assert_true(FileAccess.file_exists("%s/recovered.json" % BASE_PATH))
	assert_false(FileAccess.file_exists("%s/recovered.json.bak" % BASE_PATH))
	assert_false(FileAccess.file_exists("%s/recovered.json.tmp" % BASE_PATH))

	_cleanup_files(["profile.json", "profile.json.tmp", "profile.json.bak", "broken.json", "broken.json.corrupt", "blocked.json", "blocked.json.corrupt", "recovered.json", "recovered.json.bak", "recovered.json.tmp"])
	_cleanup_directory("blocked.json.corrupt")

func _cleanup_files(file_names: Array[String]) -> void:
	for file_name in file_names:
		var file_path := "%s/%s" % [BASE_PATH, file_name]
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))

func _cleanup_directory(directory_name: String) -> void:
	var directory_path := "%s/%s" % [BASE_PATH, directory_name]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory_path))
