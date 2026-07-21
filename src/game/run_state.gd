class_name RunState
extends RefCounted

var _values: Dictionary = {}

func _init(values: Dictionary = {}) -> void:
	_values = values.duplicate(true)

func snapshot() -> Dictionary:
	return _values.duplicate(true)

static func initial(config: Dictionary, session_id: String) -> Dictionary:
	return {
		"revision": 0,
		"session_id": session_id,
		"activity_id": config.activity_id,
		"content_version": config.content_version,
		"stage_id": config.stage_id,
		"health": config.initial_health,
		"score": 0,
		"combo": 0,
		"question_index": -1,
		"current_question": {},
		"current_seed": -1,
		"awaiting_answer": false,
		"boss_state": false,
		"earned_rewards": {},
		"paused": false,
		"timer_enabled": false,
		"timer_started_at_ms": 0,
		"timer_remaining_ms": 0,
		"completion_reason": "",
		"status": "running",
	}
