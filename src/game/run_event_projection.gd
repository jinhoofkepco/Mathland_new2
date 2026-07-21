class_name RunEventProjection
extends RefCounted

var _kind := ""
var _submitted_answer: Variant = null
var _correct_answer: Variant = null
var _correctness := false
var _response_duration_ms := 0
var _hints := 0
var _health_delta := 0
var _combo := 0
var _reward_delta: Dictionary = {}
var kind: String:
	get:
		return _kind
	set(_value):
		pass
var submitted_answer: Variant:
	get:
		return _deep_copy(_submitted_answer)
	set(_value):
		pass
var correct_answer: Variant:
	get:
		return _deep_copy(_correct_answer)
	set(_value):
		pass
var correctness: bool:
	get:
		return _correctness
	set(_value):
		pass
var response_duration_ms: int:
	get:
		return _response_duration_ms
	set(_value):
		pass
var hints: int:
	get:
		return _hints
	set(_value):
		pass
var health_delta: int:
	get:
		return _health_delta
	set(_value):
		pass
var combo: int:
	get:
		return _combo
	set(_value):
		pass
var reward_delta: Dictionary:
	get:
		return _reward_delta.duplicate(true)
	set(_value):
		pass

func _init(values: Dictionary = {}) -> void:
	_kind = values.get("kind", "")
	_submitted_answer = _deep_copy(values.get("submitted_answer", null))
	_correct_answer = _deep_copy(values.get("correct_answer", null))
	_correctness = values.get("correctness", false)
	_response_duration_ms = values.get("response_duration_ms", 0)
	_hints = values.get("hints", 0)
	_health_delta = values.get("health_delta", 0)
	_combo = values.get("combo", 0)
	var rewards: Variant = values.get("reward_delta", {})
	if rewards is Dictionary:
		_reward_delta = rewards.duplicate(true)

func to_dict() -> Dictionary:
	return {
		"kind": _kind,
		"submitted_answer": _deep_copy(_submitted_answer),
		"correct_answer": _deep_copy(_correct_answer),
		"correctness": _correctness,
		"response_duration_ms": _response_duration_ms,
		"hints": _hints,
		"health_delta": _health_delta,
		"combo": _combo,
		"reward_delta": _reward_delta.duplicate(true),
	}

static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
