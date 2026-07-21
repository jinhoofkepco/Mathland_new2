class_name RunTransition
extends RefCounted

var from_revision := -1
var kind := ""
var submitted_answer: Variant = null
var correct_answer: Variant = null
var correctness := false
var response_duration_ms := 0
var hints := 0
var health_delta := 0
var effect_name := ""
var follow_up_effect_name := ""
var effect_intensity := 1.0
var _reward_delta: Dictionary = {}
var _effect_names: Array[String] = []
var _next_state: Dictionary = {}
var reward_delta: Dictionary:
	get:
		return _reward_delta.duplicate(true)
var effect_names: Array[String]:
	get:
		return _effect_names.duplicate()
var next_state: Dictionary:
	get:
		return _next_state.duplicate(true)

func _init(values: Dictionary = {}) -> void:
	from_revision = values.get("from_revision", -1)
	kind = values.get("kind", "")
	submitted_answer = _deep_copy(values.get("submitted_answer", null))
	correct_answer = _deep_copy(values.get("correct_answer", null))
	correctness = values.get("correctness", false)
	response_duration_ms = values.get("response_duration_ms", 0)
	hints = values.get("hints", 0)
	health_delta = values.get("health_delta", 0)
	var rewards: Variant = values.get("reward_delta", {})
	if rewards is Dictionary:
		_reward_delta = rewards.duplicate(true)
	effect_name = values.get("effect_name", "")
	follow_up_effect_name = values.get("follow_up_effect_name", "")
	effect_intensity = values.get("effect_intensity", 1.0)
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
		"from_revision": from_revision,
		"kind": kind,
		"submitted_answer": _deep_copy(submitted_answer),
		"correct_answer": _deep_copy(correct_answer),
		"correctness": correctness,
		"response_duration_ms": response_duration_ms,
		"hints": hints,
		"health_delta": health_delta,
		"reward_delta": _reward_delta.duplicate(true),
		"effect_name": effect_name,
		"follow_up_effect_name": follow_up_effect_name,
		"effect_intensity": effect_intensity,
		"effect_names": _effect_names.duplicate(),
		"next_state": _next_state.duplicate(true),
	}

static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
