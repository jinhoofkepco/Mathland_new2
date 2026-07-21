class_name EventJournal
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
var _profile_id := ""
var _device_id := ""
var _path := ""
var _next_sequence := 1

func configure(profile_id: String, device_id: String, path: String) -> Dictionary:
	_profile_id = profile_id
	_device_id = device_id
	_path = path
	var replayed := replay()
	if not replayed.get("ok", false): return replayed
	for event in replayed.events: _next_sequence = maxi(_next_sequence, event.sequence + 1)
	return {"ok": true, "quarantined_tail": replayed.get("quarantined_tail", false)}

func append(payload: Dictionary) -> Dictionary:
	var event := LearningEventV1Script.create({"profile_id": _profile_id, "device_id": _device_id, "sequence": _next_sequence}, payload)
	var errors := LearningEventV1Script.validate(event)
	if not errors.is_empty(): return {"ok": false, "error": "invalid_event", "details": errors}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path.get_base_dir()))
	if directory_error != OK: return {"ok": false, "error": "journal_directory_failed"}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE_READ
	var file := FileAccess.open(_path, mode)
	if file == null: return {"ok": false, "error": "journal_open_failed"}
	file.seek_end()
	file.store_string(JSON.stringify(event) + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return {"ok": false, "error": "journal_write_failed"}
	_next_sequence += 1
	return {"ok": true, "event": event}

func replay() -> Dictionary:
	if not FileAccess.file_exists(_path): return {"ok": true, "events": [], "quarantined_tail": false}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "journal_open_failed"}
	var content := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK: return {"ok": false, "error": "journal_read_failed"}
	var complete := content.ends_with("\n")
	var lines := content.split("\n", false)
	var events: Array[Dictionary] = []
	for index in lines.size():
		var json := JSON.new()
		var parsed: Variant = json.data if json.parse(lines[index]) == OK else null
		var errors := LearningEventV1Script.validate(parsed)
		if not errors.is_empty():
			if index == lines.size() - 1 and not complete:
				return _quarantine_tail(events, lines[index])
			return {"ok": false, "error": "invalid_record", "line": index + 1}
		var event: Dictionary = parsed
		event.sequence = int(event.sequence)
		if event.sequence != events.size() + 1: return {"ok": false, "error": "invalid_sequence", "line": index + 1}
		events.append(event)
	return {"ok": true, "events": events, "quarantined_tail": false}

func unacknowledged(after_sequence: int, limit: int = 100) -> Array[Dictionary]:
	var replayed := replay()
	if not replayed.get("ok", false): return []
	var result: Array[Dictionary] = []
	for event in replayed.events:
		if event.sequence > after_sequence and result.size() < mini(limit, 100): result.append(event)
	return result

func _quarantine_tail(events: Array[Dictionary], tail: String) -> Dictionary:
	var corrupt := "%s.partial.corrupt" % _path
	var corrupt_file := FileAccess.open(corrupt, FileAccess.WRITE)
	if corrupt_file == null: return {"ok": false, "error": "tail_quarantine_failed"}
	corrupt_file.store_string(tail)
	corrupt_file.close()
	var journal := FileAccess.open(_path, FileAccess.WRITE)
	if journal == null: return {"ok": false, "error": "tail_quarantine_failed"}
	for event in events: journal.store_string(JSON.stringify(event) + "\n")
	journal.flush()
	var write_error := journal.get_error()
	journal.close()
	if write_error != OK: return {"ok": false, "error": "tail_quarantine_failed"}
	return {"ok": true, "events": events, "quarantined_tail": true}
