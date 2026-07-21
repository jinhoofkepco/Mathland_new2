class_name AtomicJsonStore
extends RefCounted

var _base_path: String

func _init(base_path: String) -> void:
	_base_path = base_path.rstrip("/")

func save(path: String, value: Variant) -> Error:
	var final_path := _path_for(path)
	var temporary_path := "%s.tmp" % final_path
	var backup_path := "%s.bak" % final_path
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(final_path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error

	if FileAccess.file_exists(backup_path):
		var remove_backup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
		if remove_backup_error != OK:
			return remove_backup_error
	if FileAccess.file_exists(final_path):
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(final_path), ProjectSettings.globalize_path(backup_path)
		)
		if backup_error != OK:
			return backup_error
	var replace_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(final_path)
	)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(final_path)
			)
		return replace_error
	if FileAccess.file_exists(backup_path):
		var remove_final_backup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
		if remove_final_backup_error != OK:
			return remove_final_backup_error
	return OK

func load(path: String) -> Dictionary:
	var final_path := _path_for(path)
	var file := FileAccess.open(final_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "not_found"}
	var content := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return {"ok": false, "error": "read_failed"}

	var json := JSON.new()
	if json.parse(content) != OK:
		var quarantine_path := "%s.corrupt" % final_path
		if FileAccess.file_exists(quarantine_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(quarantine_path))
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(final_path), ProjectSettings.globalize_path(quarantine_path)
		)
		return {"ok": false, "error": "invalid_json", "quarantine_path": quarantine_path}
	return {"ok": true, "value": json.data}

func _path_for(path: String) -> String:
	return "%s/%s" % [_base_path, path]
