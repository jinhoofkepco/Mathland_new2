class_name RecordingJournal
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")

var operations: Array[String]
var events: Array[Dictionary] = []
var fail_next_error := ""
var fail_event_type := ""
var malformed_success_next := false
var next_event_overrides: Dictionary = {}
var _profile_id: String
var _device_id: String

func _init(profile_id: String, device_id: String, shared_operations: Array[String]) -> void:
	_profile_id = profile_id
	_device_id = device_id
	operations = shared_operations

func append(payload: Dictionary) -> Dictionary:
	operations.append("journal.append")
	var event_type: String = payload.get("event_type", "")
	if not fail_next_error.is_empty():
		var error := fail_next_error
		fail_next_error = ""
		return {"ok": false, "error": error}
	if not fail_event_type.is_empty() and event_type == fail_event_type:
		return {"ok": false, "error": "disk_full"}
	var event := LearningEventV1Script.create(
		{"profile_id": _profile_id, "device_id": _device_id, "sequence": events.size() + 1},
		payload
	)
	for key in next_event_overrides:
		event[key] = next_event_overrides[key]
	next_event_overrides = {}
	var errors := LearningEventV1Script.validate(event)
	if not errors.is_empty():
		return {"ok": false, "error": "invalid_event", "details": errors}
	events.append(event.duplicate(true))
	if malformed_success_next:
		malformed_success_next = false
		return {"ok": true}
	return {"ok": true, "event": event.duplicate(true)}

func replay() -> Dictionary:
	return {"ok": true, "events": events.duplicate(true), "quarantined_tail": false}
