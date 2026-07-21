class_name LearningEventV1
extends RefCounted

const UuidV4Script = preload("res://src/core/uuid_v4.gd")

const MAX_SAFE_INTEGER := 9007199254740991
const COMMON_REQUIRED := ["contract_version", "event_id", "profile_id", "device_id", "sequence", "client_timestamp", "event_type"]
const COMMON_OPTIONAL := ["session_id"]
const RUN_STARTED := ["activity_id", "content_version"]
const ANSWER_SUBMITTED := ["activity_id", "content_version", "question_seed", "generator_id", "band_id", "resolved_parameters", "submitted_answer", "correct_answer", "correctness", "response_duration_ms", "hints", "health_delta", "combo", "reward_delta"]
const RUN_COMPLETED := ["completion_reason", "final_score", "final_health", "earned_rewards"]
const COLLECTION_UNLOCKED := ["collection_id"]
const COUPON_EARNED := ["coupon_id"]
const TYPES := ["run_started", "answer_submitted", "run_completed", "collection_unlocked", "coupon_earned"]
const SESSION_REQUIRED_TYPES := ["run_started", "answer_submitted", "run_completed"]

static func create(context: Dictionary, payload: Dictionary) -> Dictionary:
	var event := payload.duplicate(true)
	for key in context:
		event[key] = context[key]
	event["contract_version"] = 1
	event["event_id"] = UuidV4Script.generate()
	return event

static func validate(event: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not event is Dictionary:
		errors.append("not_dictionary")
		return errors
	var value: Dictionary = event
	var event_type: Variant = value.get("event_type", null)
	var type_fields := _fields_for_type(event_type)
	var allowed := COMMON_REQUIRED.duplicate()
	allowed.append_array(COMMON_OPTIONAL)
	allowed.append_array(type_fields)
	for key in value:
		if not key is String or not key in allowed:
			errors.append("unknown_%s" % key)
	for key in COMMON_REQUIRED:
		if not value.has(key):
			errors.append("missing_%s" % key)
	if event_type in SESSION_REQUIRED_TYPES and not value.has("session_id"):
		errors.append("missing_session_id")
	for key in type_fields:
		if not value.has(key):
			errors.append("missing_%s" % key)
	if not errors.is_empty():
		return errors
	if not _is_safe_integer(value.contract_version) or value.contract_version != 1 or not value.event_id is String or not UuidV4Script.is_valid(value.event_id):
		errors.append("invalid_identity")
	if not _is_nonempty_string(value.profile_id) or not _is_nonempty_string(value.device_id):
		errors.append("invalid_context")
	if value.has("session_id") and not _is_nonempty_string(value.session_id):
		errors.append("invalid_session")
	if not _is_positive_safe_integer(value.sequence):
		errors.append("invalid_sequence")
	if not _is_canonical_utc_timestamp(value.client_timestamp):
		errors.append("invalid_timestamp")
	if not event_type is String or not event_type in TYPES:
		errors.append("invalid_type")
	elif not _validate_type_fields(value, event_type):
		errors.append("invalid_%s_fields" % event_type)
	return errors

static func _fields_for_type(event_type: Variant) -> Array:
	match event_type:
		"run_started":
			return RUN_STARTED
		"answer_submitted":
			return ANSWER_SUBMITTED
		"run_completed":
			return RUN_COMPLETED
		"collection_unlocked":
			return COLLECTION_UNLOCKED
		"coupon_earned":
			return COUPON_EARNED
	return []

static func _validate_type_fields(value: Dictionary, event_type: String) -> bool:
	match event_type:
		"run_started":
			return _is_nonempty_string(value.activity_id) and _is_nonempty_string(value.content_version)
		"answer_submitted":
			return (
				_is_nonempty_string(value.activity_id)
				and _is_nonempty_string(value.content_version)
				and _is_nonnegative_safe_integer(value.question_seed)
				and _is_nonempty_string(value.generator_id)
				and _is_nonempty_string(value.band_id)
				and _is_resolved_parameters(value.resolved_parameters)
				and _is_answer_value(value.submitted_answer)
				and _is_answer_value(value.correct_answer)
				and value.correctness is bool
				and _is_nonnegative_safe_integer(value.response_duration_ms)
				and _is_nonnegative_safe_integer(value.hints)
				and _is_safe_integer(value.health_delta)
				and _is_nonnegative_safe_integer(value.combo)
				and _is_reward_map(value.reward_delta)
			)
		"run_completed":
			return (
				_is_nonempty_string(value.completion_reason)
				and _is_nonnegative_safe_integer(value.final_score)
				and _is_nonnegative_safe_integer(value.final_health)
				and _is_reward_map(value.earned_rewards)
			)
		"collection_unlocked":
			return _is_nonempty_string(value.collection_id)
		"coupon_earned":
			return _is_nonempty_string(value.coupon_id)
	return false

static func _is_answer_value(value: Variant) -> bool:
	if _is_safe_integer(value):
		return true
	if not value is Dictionary:
		return false
	var answer: Dictionary = value
	if answer.get("kind", "") == "integer":
		return _has_exact_keys(answer, ["kind", "value"]) and _is_safe_integer(answer.value)
	if answer.get("kind", "") == "integer_list":
		if not _has_exact_keys(answer, ["kind", "values", "order_matters"]) or not answer.values is Array or not answer.order_matters is bool:
			return false
		for item in answer.values:
			if not _is_safe_integer(item):
				return false
		return true
	return false

static func _is_resolved_parameters(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not _is_nonempty_string(key):
			return false
		var item: Variant = value[key]
		if item is bool or item is String or _is_finite_safe_number(item):
			continue
		if not item is Array:
			return false
		for number in item:
			if not _is_finite_safe_number(number):
				return false
	return true

static func _is_reward_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not _is_nonempty_string(key) or not _is_nonnegative_safe_integer(value[key]):
			return false
	return true

static func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

static func _is_canonical_utc_timestamp(value: Variant) -> bool:
	if not value is String:
		return false
	var expression := RegEx.new()
	if expression.compile("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z$") != OK:
		return false
	var matched := expression.search(value)
	if matched == null:
		return false
	var year := int(matched.get_string(1))
	var month := int(matched.get_string(2))
	var day := int(matched.get_string(3))
	var hour := int(matched.get_string(4))
	var minute := int(matched.get_string(5))
	var second := int(matched.get_string(6))
	if year < 1 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return false
	var days_per_month := [31, 29 if _is_leap_year(year) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day >= 1 and day <= days_per_month[month - 1]

static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)

static func _is_nonempty_string(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func _is_positive_safe_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and value > 0

static func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and value >= 0

static func _is_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER and value == floor(value)

static func _is_finite_safe_number(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
