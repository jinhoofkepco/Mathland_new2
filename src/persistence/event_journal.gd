class_name EventJournal
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")

const CORRUPT_SUFFIX := ".partial.corrupt"
const CORRUPT_TEMP_SUFFIX := ".partial.corrupt.tmp"
const CORRUPT_BACKUP_SUFFIX := ".partial.corrupt.bak"
const RECOVERY_TEMP_SUFFIX := ".recovery.tmp"
const RECOVERY_BACKUP_SUFFIX := ".recovery.bak"

var _profile_id := ""
var _device_id := ""
var _path := ""
var _next_sequence := 1

func configure(profile_id: String, device_id: String, path: String) -> Dictionary:
	_profile_id = profile_id
	_device_id = device_id
	_path = path
	_next_sequence = 1
	if _recover_interrupted_corrupt_artifact() != OK:
		return {"ok": false, "error": "tail_recovery_failed"}
	if _recover_interrupted_quarantine() != OK:
		return {"ok": false, "error": "tail_recovery_failed"}
	var replayed := replay()
	if not replayed.get("ok", false):
		return replayed
	for event in replayed.events:
		_next_sequence = maxi(_next_sequence, event.sequence + 1)
	return {"ok": true, "quarantined_tail": replayed.get("quarantined_tail", false)}

func append(payload: Dictionary) -> Dictionary:
	var event := LearningEventV1Script.create(
		{"profile_id": _profile_id, "device_id": _device_id, "sequence": _next_sequence}, payload
	)
	var errors := LearningEventV1Script.validate(event)
	if not errors.is_empty():
		return {"ok": false, "error": "invalid_event", "details": errors}
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir())
	)
	if directory_error != OK:
		return {"ok": false, "error": "journal_directory_failed"}
	var mode := FileAccess.READ_WRITE if _file_exists(_path) else FileAccess.WRITE_READ
	var file: FileAccess = _open_append_file(_path, mode)
	if file == null:
		return {"ok": false, "error": "journal_open_failed"}
	var output := PackedByteArray()
	var length := file.get_length()
	if length > 0:
		file.seek(length - 1)
		var final_byte := file.get_8()
		if file.get_error() != OK:
			file.close()
			return {"ok": false, "error": "journal_write_failed"}
		if final_byte != 0x0a:
			output.append(0x0a)
	output.append_array((JSON.stringify(event) + "\n").to_utf8_buffer())
	file.seek_end()
	var write_error := _write_append_file(file, output)
	if write_error == OK:
		write_error = _flush_append_file(file)
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "journal_write_failed"}
	_next_sequence += 1
	return {"ok": true, "event": event}

func replay() -> Dictionary:
	if not _file_exists(_path):
		return {"ok": true, "events": [], "quarantined_tail": false}
	var read_result := _read_bytes(_path)
	if not read_result.get("ok", false):
		return {"ok": false, "error": "journal_read_failed"}
	var content: PackedByteArray = read_result.bytes
	if content.is_empty():
		return {"ok": true, "events": [], "quarantined_tail": false}
	return _replay_bytes(content, true)

func unacknowledged(after_sequence: int, limit: int = 100) -> Array[Dictionary]:
	var replayed := replay()
	if not replayed.get("ok", false):
		return []
	var result: Array[Dictionary] = []
	var capped_limit := clampi(limit, 0, 100)
	for event in replayed.events:
		if event.sequence > after_sequence and result.size() < capped_limit:
			result.append(event)
	return result

func _replay_bytes(content: PackedByteArray, quarantine_syntax_tail: bool) -> Dictionary:
	var events: Array[Dictionary] = []
	var line_start := 0
	var line_number := 1
	for index in content.size():
		if content[index] != 0x0a:
			continue
		var complete_line := content.slice(line_start, index)
		var parsed_line := _validated_record(complete_line, events.size() + 1)
		if not parsed_line.get("ok", false):
			var line_error: String = parsed_line.error
			return {"ok": false, "error": "invalid_record" if line_error == "invalid_syntax" else line_error, "line": line_number}
		var event: Dictionary = parsed_line.event
		if event.profile_id != _profile_id or event.device_id != _device_id:
			return {"ok": false, "error": "scope_mismatch", "line": line_number}
		events.append(event)
		line_start = index + 1
		line_number += 1
	if line_start < content.size():
		var tail := content.slice(line_start, content.size())
		var parsed_tail := _validated_record(tail, events.size() + 1)
		if not parsed_tail.get("ok", false):
			if parsed_tail.error == "invalid_syntax":
				if not quarantine_syntax_tail:
					return {"ok": true, "events": events, "quarantined_tail": false, "recoverable_tail": true}
				var prefix := content.slice(0, line_start)
				return _quarantine_tail(events, prefix, tail)
			return {"ok": false, "error": parsed_tail.error, "line": line_number}
		var tail_event: Dictionary = parsed_tail.event
		if tail_event.profile_id != _profile_id or tail_event.device_id != _device_id:
			return {"ok": false, "error": "scope_mismatch", "line": line_number}
		events.append(tail_event)
	return {"ok": true, "events": events, "quarantined_tail": false}

func _validated_record(bytes: PackedByteArray, expected_sequence: int) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "invalid_record"}
	if not _is_valid_utf8(bytes):
		return {"ok": false, "error": "invalid_syntax"}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {"ok": false, "error": "invalid_syntax"}
	var parsed: Variant = json.data
	var errors := LearningEventV1Script.validate(parsed)
	if not errors.is_empty():
		return {"ok": false, "error": "invalid_record"}
	var event: Dictionary = parsed
	event.sequence = int(event.sequence)
	if event.sequence != expected_sequence:
		return {"ok": false, "error": "invalid_sequence"}
	return {"ok": true, "event": event}

func _quarantine_tail(events: Array[Dictionary], prefix: PackedByteArray, tail: PackedByteArray) -> Dictionary:
	var corrupt_path := "%s%s" % [_path, CORRUPT_SUFFIX]
	var corrupt_temp_path := "%s%s" % [_path, CORRUPT_TEMP_SUFFIX]
	var corrupt_backup_path := "%s%s" % [_path, CORRUPT_BACKUP_SUFFIX]
	var recovery_temp_path := "%s%s" % [_path, RECOVERY_TEMP_SUFFIX]
	var backup_path := "%s%s" % [_path, RECOVERY_BACKUP_SUFFIX]
	if _file_exists(corrupt_temp_path) or _file_exists(corrupt_backup_path) or _file_exists(recovery_temp_path) or _file_exists(backup_path):
		return {"ok": false, "error": "tail_quarantine_failed"}
	if _write_bytes(corrupt_temp_path, tail) != OK:
		return {"ok": false, "error": "tail_quarantine_failed"}
	if _write_bytes(recovery_temp_path, prefix) != OK:
		return {"ok": false, "error": "tail_quarantine_failed"}
	if _promote_corrupt_temp(corrupt_path, corrupt_temp_path, corrupt_backup_path) != OK:
		return {"ok": false, "error": "tail_quarantine_failed"}
	if _rename_path(_path, backup_path) != OK:
		return {"ok": false, "error": "tail_quarantine_failed"}
	var promotion_error := _rename_path(recovery_temp_path, _path)
	if promotion_error != OK:
		var restore_error := _rename_path(backup_path, _path)
		if restore_error != OK:
			return {"ok": false, "error": "tail_quarantine_failed"}
		return {"ok": false, "error": "tail_quarantine_failed"}
	if _remove_path(backup_path) != OK:
		return {"ok": false, "error": "tail_quarantine_failed"}
	return {"ok": true, "events": events, "quarantined_tail": true}

func _recover_interrupted_quarantine() -> Error:
	if _path.is_empty():
		return OK
	var recovery_temp_path := "%s%s" % [_path, RECOVERY_TEMP_SUFFIX]
	var backup_path := "%s%s" % [_path, RECOVERY_BACKUP_SUFFIX]
	var has_original := _file_exists(_path)
	var has_backup := _file_exists(backup_path)
	var has_recovery_temp := _file_exists(recovery_temp_path)
	if not has_backup and not has_recovery_temp:
		return OK
	var original := _journal_candidate(_path) if has_original else {"rank": 0}
	var recovery_temp := _journal_candidate(recovery_temp_path) if has_recovery_temp else {"rank": 0}
	var backup := _journal_candidate(backup_path) if has_backup else {"rank": 0}
	var selected_path := ""
	var selected_rank := 0
	for candidate in [
		{"path": _path, "info": original},
		{"path": recovery_temp_path, "info": recovery_temp},
		{"path": backup_path, "info": backup},
	]:
		var rank: int = candidate.info.get("rank", 0)
		if rank > selected_rank:
			selected_rank = rank
			selected_path = candidate.path
	if selected_rank == 0:
		return FAILED
	if selected_path == _path:
		return _remove_recovery_candidates(recovery_temp_path, backup_path)
	if not has_original:
		if _rename_path(selected_path, _path) != OK:
			return FAILED
		var other_path := backup_path if selected_path == recovery_temp_path else recovery_temp_path
		if _file_exists(other_path) and _remove_path(other_path) != OK:
			return FAILED
		return OK
	var staging_path := backup_path if selected_path == recovery_temp_path else recovery_temp_path
	if _file_exists(staging_path):
		return FAILED
	if _rename_path(_path, staging_path) != OK:
		return FAILED
	if _rename_path(selected_path, _path) != OK:
		if _rename_path(staging_path, _path) != OK:
			return FAILED
		return FAILED
	if _remove_path(staging_path) != OK:
		return FAILED
	return OK

func _recover_interrupted_corrupt_artifact() -> Error:
	if _path.is_empty():
		return OK
	var corrupt_path := "%s%s" % [_path, CORRUPT_SUFFIX]
	var temp_path := "%s%s" % [_path, CORRUPT_TEMP_SUFFIX]
	var backup_path := "%s%s" % [_path, CORRUPT_BACKUP_SUFFIX]
	var has_corrupt := _file_exists(corrupt_path)
	var has_temp := _file_exists(temp_path)
	var has_backup := _file_exists(backup_path)
	if has_backup:
		if has_corrupt:
			if has_temp:
				return FAILED
			return _remove_path(backup_path)
		if has_temp:
			if _rename_path(temp_path, corrupt_path) != OK:
				if _rename_path(backup_path, corrupt_path) != OK:
					return FAILED
				return FAILED
			if _remove_path(backup_path) != OK:
				return FAILED
			return OK
		return _rename_path(backup_path, corrupt_path)
	if has_temp:
		return _promote_corrupt_temp(corrupt_path, temp_path, backup_path)
	return OK

func _promote_corrupt_temp(corrupt_path: String, temp_path: String, backup_path: String) -> Error:
	if _file_exists(backup_path):
		return FAILED
	if not _file_exists(corrupt_path):
		return _rename_path(temp_path, corrupt_path)
	if _rename_path(corrupt_path, backup_path) != OK:
		return FAILED
	if _rename_path(temp_path, corrupt_path) != OK:
		if _rename_path(backup_path, corrupt_path) != OK:
			return FAILED
		return FAILED
	if _remove_path(backup_path) != OK:
		return FAILED
	return OK

func _journal_candidate(path: String) -> Dictionary:
	var read_result := _read_bytes(path)
	if not read_result.get("ok", false):
		return {"rank": 0}
	var content: PackedByteArray = read_result.bytes
	if content.is_empty():
		return {"rank": 2}
	var inspected := _replay_bytes(content, false)
	if not inspected.get("ok", false):
		return {"rank": 0}
	return {"rank": 1 if inspected.get("recoverable_tail", false) else 2}

func _remove_recovery_candidates(recovery_temp_path: String, backup_path: String) -> Error:
	if _file_exists(recovery_temp_path) and _remove_path(recovery_temp_path) != OK:
		return FAILED
	if _file_exists(backup_path) and _remove_path(backup_path) != OK:
		return FAILED
	return OK

func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var bytes := file.get_buffer(file.get_length())
	var read_error := file.get_error()
	file.close()
	return {"ok": read_error == OK, "bytes": bytes}

func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error

func _open_append_file(path: String, mode: int) -> FileAccess:
	return FileAccess.open(path, mode)

func _write_append_file(file: FileAccess, bytes: PackedByteArray) -> Error:
	file.store_buffer(bytes)
	return file.get_error()

func _flush_append_file(file: FileAccess) -> Error:
	file.flush()
	return file.get_error()

func _rename_path(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)
	)

func _remove_path(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func _is_valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first := bytes[index]
		if first <= 0x7f:
			index += 1
			continue
		if first >= 0xc2 and first <= 0xdf:
			if index + 1 >= bytes.size() or not _is_continuation(bytes[index + 1]):
				return false
			index += 2
			continue
		if first >= 0xe0 and first <= 0xef:
			if index + 2 >= bytes.size() or not _is_continuation(bytes[index + 2]):
				return false
			var second := bytes[index + 1]
			if (first == 0xe0 and (second < 0xa0 or second > 0xbf)) or (first == 0xed and (second < 0x80 or second > 0x9f)) or (first != 0xe0 and first != 0xed and not _is_continuation(second)):
				return false
			index += 3
			continue
		if first >= 0xf0 and first <= 0xf4:
			if index + 3 >= bytes.size() or not _is_continuation(bytes[index + 2]) or not _is_continuation(bytes[index + 3]):
				return false
			var second := bytes[index + 1]
			if (first == 0xf0 and (second < 0x90 or second > 0xbf)) or (first == 0xf4 and (second < 0x80 or second > 0x8f)) or (first != 0xf0 and first != 0xf4 and not _is_continuation(second)):
				return false
			index += 4
			continue
		return false
	return true

func _is_continuation(byte: int) -> bool:
	return byte >= 0x80 and byte <= 0xbf
