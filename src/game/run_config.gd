class_name RunConfig
extends RefCounted

const MAX_SAFE_INTEGER := 9007199254740991

var activity_id := ""
var content_version := ""
var stage_id := ""
var boss_question_indices: Array[int] = []
var boss_every_correct := 0
var initial_health := 0
var target_score := 0
var timer_allowed := false
var timer_duration_ms := 0
var reward_per_correct: Dictionary = {}
var reward_on_completion: Dictionary = {}
var combo_thresholds: Array[int] = []
var effect_presets: Dictionary = {}
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
	var raw_boss_every: Variant = values.get("boss_every_correct", 0)
	_shape_valid = (
		raw_activity is String
		and raw_version is String
		and raw_stage is String
		and _is_integer_number(raw_health)
		and _is_integer_number(raw_target)
		and raw_timer_allowed is bool
		and _is_integer_number(raw_timer_duration)
		and _is_integer_number(raw_boss_every)
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
		boss_every_correct = int(raw_boss_every)
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
	var completion_rewards: Variant = values.get("reward_on_completion", {})
	if completion_rewards is Dictionary:
		for key in completion_rewards:
			if _is_integer_number(completion_rewards[key]):
				reward_on_completion[key] = int(completion_rewards[key])
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
	var effects: Variant = values.get("effect_presets", _default_effect_presets())
	if effects is Dictionary:
		effect_presets = effects.duplicate(true)
	else:
		_shape_valid = false

func is_valid() -> bool:
	if not _shape_valid or activity_id.is_empty() or content_version.is_empty() or stage_id.is_empty():
		return false
	if not _is_positive_safe_integer(initial_health) or not _is_positive_safe_integer(target_score):
		return false
	if not _is_nonnegative_safe_integer(timer_duration_ms):
		return false
	if not _is_nonnegative_safe_integer(boss_every_correct):
		return false
	if not is_finite(effect_intensity) or effect_intensity < 0.0 or effect_intensity > 1.0:
		return false
	var seen_bosses := {}
	for index in boss_question_indices:
		if index < 0 or index in seen_bosses:
			return false
		seen_bosses[index] = true
	var previous := 0
	if combo_thresholds.size() > 3:
		return false
	for threshold in combo_thresholds:
		if threshold <= previous or not _is_positive_safe_integer(threshold):
			return false
		previous = threshold
	for key in reward_per_correct:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(reward_per_correct[key]):
			return false
		if float(reward_per_correct[key]) * float(target_score) + float(reward_on_completion.get(key, 0)) > float(MAX_SAFE_INTEGER):
			return false
	for key in reward_on_completion:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(reward_on_completion[key]):
			return false
		if not reward_per_correct.has(key) and reward_on_completion[key] > MAX_SAFE_INTEGER:
			return false
	var required_effects := _default_effect_presets().keys()
	if effect_presets.size() != required_effects.size():
		return false
	for key in required_effects:
		if not effect_presets.get(key) is String or effect_presets.get(key).is_empty():
			return false
	return true

func to_dict() -> Dictionary:
	return {
		"activity_id": activity_id,
		"content_version": content_version,
		"stage_id": stage_id,
		"boss_question_indices": boss_question_indices.duplicate(),
		"boss_every_correct": boss_every_correct,
		"initial_health": initial_health,
		"target_score": target_score,
		"timer_allowed": timer_allowed,
		"timer_duration_ms": timer_duration_ms,
		"reward_per_correct": reward_per_correct.duplicate(true),
		"reward_on_completion": reward_on_completion.duplicate(true),
		"combo_thresholds": combo_thresholds.duplicate(),
		"effect_presets": effect_presets.duplicate(true),
		"effect_intensity": effect_intensity,
	}

static func from_activity(activity: Dictionary) -> RefCounted:
	var run_value: Variant = activity.get("run")
	var v1_bands: Variant = activity.get("difficulty_bands")
	if run_value is Dictionary and v1_bands is Array:
		return _from_v1_activity(activity, run_value, v1_bands)
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
		"boss_every_correct": 0,
		"initial_health": activity.get("initial_health", 0),
		"target_score": activity.get("target_score", 0),
		"timer_allowed": timer.get("enabled", null) if timer is Dictionary else null,
		"timer_duration_ms": timer.get("duration_ms", null) if timer is Dictionary else null,
		"reward_per_correct": activity.get("reward_per_correct", {}),
		"reward_on_completion": {},
		"combo_thresholds": activity.get("combo_thresholds", [2, 4]),
		"effect_presets": _default_effect_presets(),
		"effect_intensity": activity.get("effect_intensity", 1.0),
	}
	return load("res://src/game/run_config.gd").new(values)

static func _from_v1_activity(activity: Dictionary, run: Dictionary, bands: Array) -> RefCounted:
	var stage := ""
	if not bands.is_empty() and bands[0] is Dictionary:
		stage = String(bands[0].get("band_id", ""))
	var goal: Variant = run.get("goal", {})
	var timer: Variant = run.get("timer", {})
	var rewards: Variant = run.get("rewards", {})
	var seconds: Variant = timer.get("seconds", null) if timer is Dictionary else null
	var duration: Variant = null
	if _is_integer_number(seconds) and seconds >= 0 and seconds <= MAX_SAFE_INTEGER / 1000:
		duration = int(seconds) * 1000
	var reward_per_correct: Variant = {}
	var reward_on_completion: Variant = {}
	if rewards is Dictionary:
		reward_per_correct = {"apples": rewards.get("apples_per_correct", null)}
		reward_on_completion = {"apples": rewards.get("completion_apples", null)}
	var values := {
		"activity_id": activity.get("activity_id", ""),
		"content_version": activity.get("content_version", ""),
		"stage_id": stage,
		"boss_question_indices": [],
		"boss_every_correct": run.get("boss_every_correct", null),
		"initial_health": run.get("starting_hearts", null),
		"target_score": goal.get("target", null) if goal is Dictionary and goal.get("kind") == "correct_answers" else null,
		"timer_allowed": timer.get("enabled", null) if timer is Dictionary else null,
		"timer_duration_ms": duration,
		"reward_per_correct": reward_per_correct,
		"reward_on_completion": reward_on_completion,
		"combo_thresholds": run.get("combo_thresholds", []),
		"effect_presets": run.get("effects", null),
		"effect_intensity": 1.0,
	}
	return load("res://src/game/run_config.gd").new(values)

static func _default_effect_presets() -> Dictionary:
	return {
		"correct": "correct",
		"wrong": "wrong",
		"combo": "combo_1",
		"boss": "boss",
		"level_up": "level_up",
		"reward": "reward",
		"health_loss": "health_loss",
	}

static func _is_positive_safe_integer(value: Variant) -> bool:
	return value is int and value > 0 and value <= MAX_SAFE_INTEGER

static func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_SAFE_INTEGER

static func _is_integer_number(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value == floor(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
