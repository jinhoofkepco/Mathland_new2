class_name ProgressReducer
extends RefCounted

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")

const MAX_SAFE_INTEGER := 9007199254740991
const STATE_KEYS := [
	"schema_version",
	"profile_id",
	"last_sequence",
	"apples",
	"inventory",
	"collections",
	"coupons",
	"pending_review",
	"activity_progress",
	"run_totals",
]
const ACTIVITY_KEYS := ["attempts", "correct", "repeated_errors"]
const RUN_TOTAL_KEYS := ["completed", "health_depleted"]

static func initial_state(profile_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"profile_id": profile_id,
		"last_sequence": 0,
		"apples": 0,
		"inventory": {},
		"collections": [],
		"coupons": [],
		"pending_review": 0,
		"activity_progress": {},
		"run_totals": {"completed": 0, "health_depleted": 0},
	}

static func apply(state: Dictionary, event: Variant) -> Dictionary:
	var unchanged := state.duplicate(true)
	if not _can_reduce(state) or not LearningEventV1Script.validate(event).is_empty():
		return unchanged
	var event_value: Dictionary = event
	if event_value.profile_id != state.profile_id:
		return unchanged
	var event_sequence := int(event_value.sequence)
	if event_sequence <= int(state.last_sequence):
		return unchanged

	var next := state.duplicate(true)
	match event_value.event_type:
		"answer_submitted":
			if not _apply_answer(next, event_value):
				return unchanged
		"run_completed":
			if not _apply_run_completed(next, event_value):
				return unchanged
		"collection_unlocked":
			_append_unique(next.collections, event_value.collection_id)
		"coupon_earned":
			_append_unique(next.coupons, event_value.coupon_id)
		"run_started":
			pass
		_:
			return unchanged
	next.last_sequence = event_sequence
	return next

static func _apply_answer(state: Dictionary, event: Dictionary) -> bool:
	var activity_id: String = event.activity_id
	var activity: Dictionary = state.activity_progress.get(
		activity_id, {"attempts": 0, "correct": 0, "repeated_errors": {}}
	).duplicate(true)
	if not _increment_safe(activity, "attempts", 1):
		return false
	if event.correctness:
		if not _increment_safe(activity, "correct", 1):
			return false
	else:
		if not _increment_safe(state, "pending_review", 1):
			return false
		var repeated_errors: Dictionary = activity.repeated_errors
		var error_key := _repeated_error_key(event)
		if not _increment_safe(repeated_errors, error_key, 1):
			return false
		activity.repeated_errors = repeated_errors
	state.activity_progress[activity_id] = activity

	var inventory: Dictionary = state.inventory
	for reward_name in event.reward_delta:
		var reward_delta := int(event.reward_delta[reward_name])
		if reward_name == "apples":
			if not _increment_safe(state, "apples", reward_delta):
				return false
		elif not _increment_safe(inventory, reward_name, reward_delta):
			return false
	state.inventory = inventory
	return true

static func _apply_run_completed(state: Dictionary, event: Dictionary) -> bool:
	var run_totals: Dictionary = state.run_totals
	if event.completion_reason == "health_depleted":
		if not _increment_safe(run_totals, "health_depleted", 1):
			return false
	else:
		if not _increment_safe(run_totals, "completed", 1):
			return false
	state.run_totals = run_totals
	return true

static func _repeated_error_key(event: Dictionary) -> String:
	return JSON.stringify(_normalize_key_value(
		{
			"activity_id": event.activity_id,
			"band_id": event.band_id,
			"correct_answer": event.correct_answer,
			"generator_id": event.generator_id,
			"resolved_parameters": event.resolved_parameters,
		}
	))

static func _normalize_key_value(value: Variant) -> Variant:
	if (
		value is float
		and is_finite(value)
		and value >= -MAX_SAFE_INTEGER
		and value <= MAX_SAFE_INTEGER
		and value == floor(value)
	):
		return int(value)
	if value is Dictionary:
		var normalized_dictionary := {}
		for key in value:
			normalized_dictionary[key] = _normalize_key_value(value[key])
		return normalized_dictionary
	if value is Array:
		var normalized_array := []
		for item in value:
			normalized_array.append(_normalize_key_value(item))
		return normalized_array
	return value

static func _append_unique(values: Array, value: String) -> void:
	if not value in values:
		values.append(value)

static func _increment_safe(target: Dictionary, key: Variant, delta: int) -> bool:
	var current: Variant = target.get(key, 0)
	if not _is_nonnegative_safe_integer(current) or delta < 0:
		return false
	var total := int(current) + delta
	if total > MAX_SAFE_INTEGER:
		return false
	target[key] = total
	return true

static func _can_reduce(state: Dictionary) -> bool:
	if not _has_exact_keys(state, STATE_KEYS):
		return false
	if (
		not _is_nonnegative_safe_integer(state.schema_version)
		or int(state.schema_version) != 1
		or not state.profile_id is String
		or state.profile_id.is_empty()
		or not _is_nonnegative_safe_integer(state.last_sequence)
		or not _is_nonnegative_safe_integer(state.apples)
		or not _is_nonnegative_safe_integer(state.pending_review)
		or not state.inventory is Dictionary
		or state.inventory.has("apples")
		or not _is_count_map(state.inventory, true)
		or not state.collections is Array
		or not _is_unique_string_array(state.collections)
		or not state.coupons is Array
		or not _is_unique_string_array(state.coupons)
		or not state.activity_progress is Dictionary
		or not state.run_totals is Dictionary
		or not _has_exact_keys(state.run_totals, RUN_TOTAL_KEYS)
	):
		return false
	for total_key in RUN_TOTAL_KEYS:
		if not _is_nonnegative_safe_integer(state.run_totals[total_key]):
			return false
	for activity_id in state.activity_progress:
		if not activity_id is String or activity_id.is_empty():
			return false
		var activity: Variant = state.activity_progress[activity_id]
		if not activity is Dictionary or not _has_exact_keys(activity, ACTIVITY_KEYS):
			return false
		if (
			not _is_nonnegative_safe_integer(activity.attempts)
			or not _is_nonnegative_safe_integer(activity.correct)
			or int(activity.correct) > int(activity.attempts)
			or not activity.repeated_errors is Dictionary
			or not _is_count_map(activity.repeated_errors, false)
		):
			return false
	return true

static func _has_exact_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key in expected_keys:
		if not value.has(key):
			return false
	return true

static func _is_count_map(value: Dictionary, allow_zero: bool) -> bool:
	for key in value:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(value[key]):
			return false
		if not allow_zero and int(value[key]) == 0:
			return false
	return true

static func _is_unique_string_array(value: Array) -> bool:
	var seen := {}
	for item in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true

static func _is_nonnegative_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0 and value <= MAX_SAFE_INTEGER
	return (
		value is float
		and is_finite(value)
		and value >= 0
		and value <= MAX_SAFE_INTEGER
		and value == floor(value)
	)
