class_name InMemoryProgressService
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const ProgressReducerScript = preload("res://src/progress/progress_reducer.gd")

var operations: Array[String]
var committed_events: Array[Dictionary] = []
var fail_next_error: Error = OK
var _state: Dictionary

func _init(profile_id: String, shared_operations: Array[String]) -> void:
	operations = shared_operations
	_state = ProgressReducerScript.initial_state(profile_id)

func commit(event: Dictionary) -> Error:
	operations.append("progress.commit")
	if fail_next_error != OK:
		var error := fail_next_error
		fail_next_error = OK
		return error
	if not LearningEventV1Script.validate(event).is_empty():
		return ERR_INVALID_DATA
	var next := ProgressReducerScript.apply(_state, event)
	if int(next.get("last_sequence", -1)) != int(event.sequence):
		return ERR_INVALID_DATA
	_state = next
	committed_events.append(event.duplicate(true))
	return OK

func snapshot() -> Dictionary:
	return _state.duplicate(true)
