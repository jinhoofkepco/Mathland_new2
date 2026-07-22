class_name RunTransition
extends RefCounted

var _from_revision := -1
var _kind := ""
var _submitted_answer: Variant = null
var _correct_answer: Variant = null
var _correctness := false
var _response_duration_ms := 0
var _hints := 0
var _health_delta := 0
var _effect_name := ""
var _follow_up_effect_name := ""
var _effect_intensity := 1.0
var _reward_delta: Dictionary = {}
var _effect_names: Array[String] = []
var _next_state: Dictionary = {}
var from_revision: int:
	get:
		return _from_revision
	set(_value):
		pass
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
var effect_name: String:
	get:
		return _effect_name
	set(_value):
		pass
var follow_up_effect_name: String:
	get:
		return _follow_up_effect_name
	set(_value):
		pass
var effect_intensity: float:
	get:
		return _effect_intensity
	set(_value):
		pass
var reward_delta: Dictionary:
	get:
		return _reward_delta.duplicate(true)
	set(_value):
		pass
var effect_names: Array[String]:
	get:
		return _effect_names.duplicate()
	set(_value):
		pass
var next_state: Dictionary:
	get:
		return _next_state.duplicate(true)
	set(_value):
		pass

func _init(values: Dictionary = {}) -> void:
	_from_revision = values.get("from_revision", -1)
	_kind = values.get("kind", "")
	_submitted_answer = _deep_copy(values.get("submitted_answer", null))
	_correct_answer = _deep_copy(values.get("correct_answer", null))
	_correctness = values.get("correctness", false)
	_response_duration_ms = values.get("response_duration_ms", 0)
	_hints = values.get("hints", 0)
	_health_delta = values.get("health_delta", 0)
	var rewards: Variant = values.get("reward_delta", {})
	if rewards is Dictionary:
		_reward_delta = rewards.duplicate(true)
	_effect_name = values.get("effect_name", "")
	_follow_up_effect_name = values.get("follow_up_effect_name", "")
	_effect_intensity = values.get("effect_intensity", 1.0)
	var effects: Variant = values.get("effect_names", [])
	if effects is Array:
		for effect in effects:
			if effect is String:
				_effect_names.append(effect)
	var state: Variant = values.get("next_state", {})
	if state is Dictionary:
		_next_state = state.duplicate(true)

func duplicate_transition() -> RefCounted:
	return get_script().new(to_dict())

func to_dict() -> Dictionary:
	return {
		"from_revision": _from_revision,
		"kind": _kind,
		"submitted_answer": _deep_copy(_submitted_answer),
		"correct_answer": _deep_copy(_correct_answer),
		"correctness": _correctness,
		"response_duration_ms": _response_duration_ms,
		"hints": _hints,
		"health_delta": _health_delta,
		"reward_delta": _reward_delta.duplicate(true),
		"effect_name": _effect_name,
		"follow_up_effect_name": _follow_up_effect_name,
		"effect_intensity": _effect_intensity,
		"effect_names": _effect_names.duplicate(),
		"next_state": _next_state.duplicate(true),
	}

static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
