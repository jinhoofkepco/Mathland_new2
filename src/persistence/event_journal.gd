class_name EventJournal
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")

const CORRUPT_SUFFIX := ".partial.corrupt"
const CORRUPT_TEMP_SUFFIX := ".partial.corrupt.tmp"
const CORRUPT_BACKUP_SUFFIX := ".partial.corrupt.bak"
const RECOVERY_TEMP_SUFFIX := ".recovery.tmp"
const RECOVERY_BACKUP_SUFFIX := ".recovery.bak"
const RECOVERY_ROTATION_SUFFIX := ".recovery.rotate"
const RECOVERY_STAGE_SUFFIX := ".recovery.stage"
const APPEND_ROLLBACK_TEMP_SUFFIX := ".append.rollback.tmp"
const APPEND_FAILED_BACKUP_SUFFIX := ".append.failed.bak"

var _profile_id := ""
var _device_id := ""
var _path := ""
var _next_sequence := 1
var _append_blocked := false

func configure(profile_id: String, device_id: String, path: String) -> Dictionary:
	_profile_id = profile_id
	_device_id = device_id
	_path = path
	_next_sequence = 1
	if _recover_interrupted_corrupt_artifact() != OK:
		return {"ok": false, "error": "tail_recovery_failed"}
	var interrupted_recovery := _recover_interrupted_quarantine()
	if not interrupted_recovery.get("ok", false):
		return interrupted_recovery
	var replayed := replay()
	if not replayed.get("ok", false):
		return replayed
	for event in replayed.events:
		_next_sequence = maxi(_next_sequence, event.sequence + 1)
	_append_blocked = false
	return {"ok": true, "quarantined_tail": replayed.get("quarantined_tail", false)}

func append(payload: Dictionary) -> Dictionary:
	if _append_blocked:
		return {"ok": false, "error": "append_recovery_required"}
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
	var existed_before := _file_exists(_path)
	var before := PackedByteArray()
	if existed_before:
		var snapshot := _read_bytes(_path)
		if not snapshot.get("ok", false):
			return {"ok": false, "error": "journal_read_failed"}
		before = snapshot.bytes
	var output := PackedByteArray()
	if not before.is_empty() and before[-1] != 0x0a:
		output.append(0x0a)
	output.append_array((JSON.stringify(event) + "\n").to_utf8_buffer())
	var mode := FileAccess.READ_WRITE if existed_before else FileAccess.WRITE_READ
	var file: FileAccess = _open_append_file(_path, mode)
	if file == null:
		return {"ok": false, "error": "journal_open_failed"}
	if file.get_length() != before.size():
		file.close()
		_append_blocked = true
		return {"ok": false, "error": "append_recovery_required"}
	file.seek_end()
	var write_error := _write_append_file(file, output)
	if write_error == OK:
		write_error = _flush_append_file(file)
	file.close()
	if write_error != OK:
		return _reconcile_failed_append(before, output, event)
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
	var rotation_path := "%s%s" % [_path, RECOVERY_ROTATION_SUFFIX]
	var stage_path := "%s%s" % [_path, RECOVERY_STAGE_SUFFIX]
	var append_temp_path := "%s%s" % [_path, APPEND_ROLLBACK_TEMP_SUFFIX]
	var append_backup_path := "%s%s" % [_path, APPEND_FAILED_BACKUP_SUFFIX]
	if _file_exists(corrupt_temp_path) or _file_exists(corrupt_backup_path) or _file_exists(recovery_temp_path) or _file_exists(backup_path) or _file_exists(rotation_path) or _file_exists(stage_path) or _file_exists(append_temp_path) or _file_exists(append_backup_path):
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

func _recover_interrupted_quarantine() -> Dictionary:
	if _path.is_empty():
		return {"ok": true}
	var auxiliary_paths := [
		"%s%s" % [_path, RECOVERY_TEMP_SUFFIX],
		"%s%s" % [_path, RECOVERY_BACKUP_SUFFIX],
		"%s%s" % [_path, RECOVERY_ROTATION_SUFFIX],
		"%s%s" % [_path, RECOVERY_STAGE_SUFFIX],
		"%s%s" % [_path, APPEND_ROLLBACK_TEMP_SUFFIX],
		"%s%s" % [_path, APPEND_FAILED_BACKUP_SUFFIX],
	]
	var has_auxiliary := false
	for path in auxiliary_paths:
		if _file_exists(path):
			has_auxiliary = true
			break
	if not has_auxiliary:
		return {"ok": true}
	var ordered_paths: Array[String] = [_path]
	for path in auxiliary_paths:
		ordered_paths.append(path)
	var selected := {}
	var has_scope_mismatch := false
	for precedence in ordered_paths.size():
		var path := ordered_paths[precedence]
		if not _file_exists(path):
			continue
		var candidate := _journal_candidate(path)
		candidate["path"] = path
		candidate["precedence"] = precedence
		if candidate.get("error", "") == "scope_mismatch":
			has_scope_mismatch = true
		if _candidate_is_better(candidate, selected):
			selected = candidate
	if not selected.get("valid", false):
		return {"ok": false, "error": "tail_recovery_failed"}
	if selected.get("event_count", 0) == 0 and has_scope_mismatch:
		return {"ok": false, "error": "scope_mismatch"}
	if _promote_journal_candidate(selected.path, auxiliary_paths) != OK:
		return {"ok": false, "error": "tail_recovery_failed"}
	return {"ok": true}

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
		return {"valid": false}
	var content: PackedByteArray = read_result.bytes
	if content.is_empty():
		return {"valid": true, "event_count": 0, "last_sequence": 0, "complete": true}
	var inspected := _replay_bytes(content, false)
	if not inspected.get("ok", false):
		return {"valid": false, "error": inspected.get("error", "invalid_candidate")}
	var events: Array[Dictionary] = inspected.events
	var last_sequence := 0 if events.is_empty() else int(events[-1].sequence)
	return {
		"valid": true,
		"event_count": events.size(),
		"last_sequence": last_sequence,
		"complete": not inspected.get("recoverable_tail", false),
	}

func _candidate_is_better(candidate: Dictionary, current: Dictionary) -> bool:
	if not candidate.get("valid", false):
		return false
	if not current.get("valid", false):
		return true
	if candidate.event_count != current.event_count:
		return candidate.event_count > current.event_count
	if candidate.last_sequence != current.last_sequence:
		return candidate.last_sequence > current.last_sequence
	if candidate.complete != current.complete:
		return candidate.complete
	return candidate.precedence < current.precedence

func _promote_journal_candidate(selected_path: String, auxiliary_paths: Array) -> Error:
	if selected_path == _path:
		return _remove_paths(auxiliary_paths)
	if not _file_exists(_path):
		if _rename_path(selected_path, _path) != OK:
			return FAILED
		return _remove_paths(auxiliary_paths)
	var rotation_paths := [
		"%s%s" % [_path, RECOVERY_ROTATION_SUFFIX],
		"%s%s" % [_path, RECOVERY_STAGE_SUFFIX],
	]
	var rotation_path := ""
	for candidate_path in rotation_paths:
		if candidate_path != selected_path and not _file_exists(candidate_path):
			rotation_path = candidate_path
			break
	if rotation_path.is_empty():
		return FAILED
	if _rename_path(_path, rotation_path) != OK:
		return FAILED
	if _rename_path(selected_path, _path) != OK:
		if _rename_path(rotation_path, _path) != OK:
			return FAILED
		return FAILED
	return _remove_paths(auxiliary_paths)

func _remove_paths(paths: Array) -> Error:
	for path in paths:
		if _file_exists(path) and _remove_path(path) != OK:
			return FAILED
	return OK

func _reconcile_failed_append(before: PackedByteArray, output: PackedByteArray, event: Dictionary) -> Dictionary:
	if not _file_exists(_path):
		if before.is_empty():
			return {"ok": false, "error": "journal_write_failed"}
		_append_blocked = true
		return {"ok": false, "error": "append_recovery_required"}
	var read_result := _read_bytes(_path)
	if not read_result.get("ok", false):
		_append_blocked = true
		return {"ok": false, "error": "append_recovery_required"}
	var actual: PackedByteArray = read_result.bytes
	var committed := before.duplicate()
	committed.append_array(output)
	if actual == committed:
		_next_sequence += 1
		return {"ok": true, "event": event}
	if not output.is_empty() and output[-1] == 0x0a:
		var committed_without_newline := committed.slice(0, committed.size() - 1)
		if actual == committed_without_newline:
			_next_sequence += 1
			return {"ok": true, "event": event}
	if actual == before:
		return {"ok": false, "error": "journal_write_failed"}
	if _bytes_start_with(actual, before):
		var suffix := actual.slice(before.size(), actual.size())
		if suffix.size() < output.size() and output.slice(0, suffix.size()) == suffix:
			if _rollback_partial_append(before) == OK:
				return {"ok": false, "error": "journal_write_failed"}
	_append_blocked = true
	return {"ok": false, "error": "append_recovery_required"}

func _rollback_partial_append(before: PackedByteArray) -> Error:
	var temp_path := "%s%s" % [_path, APPEND_ROLLBACK_TEMP_SUFFIX]
	var backup_path := "%s%s" % [_path, APPEND_FAILED_BACKUP_SUFFIX]
	if _file_exists(temp_path) or _file_exists(backup_path):
		return FAILED
	if _write_bytes(temp_path, before) != OK:
		return FAILED
	if _rename_path(_path, backup_path) != OK:
		return FAILED
	if _rename_path(temp_path, _path) != OK:
		if _rename_path(backup_path, _path) != OK:
			return FAILED
		return FAILED
	if _remove_path(backup_path) != OK:
		return FAILED
	return OK

func _bytes_start_with(bytes: PackedByteArray, prefix: PackedByteArray) -> bool:
	return bytes.size() >= prefix.size() and bytes.slice(0, prefix.size()) == prefix

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
