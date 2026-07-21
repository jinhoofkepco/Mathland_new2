class_name RunConfig
extends RefCounted

const MAX_SAFE_INTEGER := 9007199254740991

var activity_id := ""
var content_version := ""
var stage_id := ""
var boss_question_indices: Array[int] = []
var initial_health := 0
var target_score := 0
var timer_allowed := false
var timer_duration_ms := 0
var reward_per_correct: Dictionary = {}
var combo_thresholds: Array[int] = []
var effect_intensity := 1.0
var _shape_valid := true

func _init(values: Dictionary = {}) -> void:
	var raw_activity: Variant = values.get("activity_id", "")
	var raw_version: Variant = values.get("content_version", "")
	var raw_stage: Variant = values.get("stage_id", "")
	var raw_health: Variant = values.get("initial_health", 0)
	var raw_target: Variant = values.get("target_score", 0)
	var raw_timer_allowed: Variant = values.get("timer_allowed", false)
	var raw_timer_duration: Variant = values.get("timer_duration_ms", 0)
	var raw_intensity: Variant = values.get("effect_intensity", 1.0)
	_shape_valid = (
		raw_activity is String
		and raw_version is String
		and raw_stage is String
		and _is_integer_number(raw_health)
		and _is_integer_number(raw_target)
		and raw_timer_allowed is bool
		and _is_integer_number(raw_timer_duration)
		and (raw_intensity is float or raw_intensity is int)
	)
	if _shape_valid:
		activity_id = raw_activity
		content_version = raw_version
		stage_id = raw_stage
		initial_health = int(raw_health)
		target_score = int(raw_target)
		timer_allowed = raw_timer_allowed
		timer_duration_ms = int(raw_timer_duration)
		effect_intensity = float(raw_intensity)
	var bosses: Variant = values.get("boss_question_indices", [])
	if bosses is Array:
		for value in bosses:
			if _is_integer_number(value):
				boss_question_indices.append(int(value))
			else:
				_shape_valid = false
	else:
		_shape_valid = false
	var rewards: Variant = values.get("reward_per_correct", {})
	if rewards is Dictionary:
		for key in rewards:
			if _is_integer_number(rewards[key]):
				reward_per_correct[key] = int(rewards[key])
			else:
				_shape_valid = false
	else:
		_shape_valid = false
	var thresholds: Variant = values.get("combo_thresholds", [])
	if thresholds is Array:
		for value in thresholds:
			if _is_integer_number(value):
				combo_thresholds.append(int(value))
			else:
				_shape_valid = false
	else:
		_shape_valid = false

func is_valid() -> bool:
	if not _shape_valid or activity_id.is_empty() or content_version.is_empty() or stage_id.is_empty():
		return false
	if not _is_positive_safe_integer(initial_health) or not _is_positive_safe_integer(target_score):
		return false
	if not _is_nonnegative_safe_integer(timer_duration_ms):
		return false
	if not is_finite(effect_intensity) or effect_intensity < 0.0 or effect_intensity > 1.0:
		return false
	var seen_bosses := {}
	for index in boss_question_indices:
		if index < 0 or index in seen_bosses:
			return false
		seen_bosses[index] = true
	var previous := 0
	if combo_thresholds.size() > 2:
		return false
	for threshold in combo_thresholds:
		if threshold <= previous or not _is_positive_safe_integer(threshold):
			return false
		previous = threshold
	for key in reward_per_correct:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(reward_per_correct[key]):
			return false
		if float(reward_per_correct[key]) * float(target_score) > float(MAX_SAFE_INTEGER):
			return false
	return true

func to_dict() -> Dictionary:
	return {
		"activity_id": activity_id,
		"content_version": content_version,
		"stage_id": stage_id,
		"boss_question_indices": boss_question_indices.duplicate(),
		"initial_health": initial_health,
		"target_score": target_score,
		"timer_allowed": timer_allowed,
		"timer_duration_ms": timer_duration_ms,
		"reward_per_correct": reward_per_correct.duplicate(true),
		"combo_thresholds": combo_thresholds.duplicate(),
		"effect_intensity": effect_intensity,
	}

static func from_activity(activity: Dictionary) -> RefCounted:
	var timer: Variant = activity.get("timer", {})
	var bands: Variant = activity.get("bands", [])
	var stage := ""
	if bands is Array and not bands.is_empty() and bands[0] is Dictionary:
		stage = bands[0].get("band_id", "")
	var values := {
		"activity_id": activity.get("activity_id", ""),
		"content_version": activity.get("content_version", ""),
		"stage_id": activity.get("stage_id", stage),
		"boss_question_indices": activity.get("boss_question_indices", []),
		"initial_health": activity.get("initial_health", 0),
		"target_score": activity.get("target_score", 0),
		"timer_allowed": timer.get("enabled", null) if timer is Dictionary else null,
		"timer_duration_ms": timer.get("duration_ms", null) if timer is Dictionary else null,
		"reward_per_correct": activity.get("reward_per_correct", {}),
		"combo_thresholds": activity.get("combo_thresholds", [2, 4]),
		"effect_intensity": activity.get("effect_intensity", 1.0),
	}
	return load("res://src/game/run_config.gd").new(values)

static func _is_positive_safe_integer(value: Variant) -> bool:
	return value is int and value > 0 and value <= MAX_SAFE_INTEGER

static func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_SAFE_INTEGER

static func _is_integer_number(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value == floor(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
