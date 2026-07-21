class_name LearningEventV1
extends RefCounted

const UuidV4Script = preload("res://src/core/uuid_v4.gd")
const COMMON := ["contract_version", "event_id", "profile_id", "device_id", "session_id", "sequence", "client_timestamp", "event_type"]
const ANSWER := ["activity_id", "content_version", "question_seed", "generator_id", "band_id", "resolved_parameters", "submitted_answer", "correct_answer", "correctness", "response_duration_ms", "hints", "health_delta", "combo", "reward_delta"]
const TYPES := ["run_started", "answer_submitted", "run_completed", "collection_unlocked", "coupon_earned"]

static func create(context: Dictionary, payload: Dictionary) -> Dictionary:
	var event := context.duplicate(true)
	for key in payload:
		event[key] = payload[key]
	event.contract_version = 1
	event.event_id = UuidV4Script.generate()
	return event

static func validate(event: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not event is Dictionary:
		errors.append("not_dictionary")
		return errors
	var value: Dictionary = event
	var allowed := COMMON.duplicate()
	if value.get("event_type", "") == "answer_submitted":
		allowed.append_array(ANSWER)
	for key in value:
		if not key in allowed:
			errors.append("unknown_%s" % key)
	for key in COMMON:
		if not value.has(key):
			errors.append("missing_%s" % key)
	if not errors.is_empty():
		return errors
	if value.contract_version != 1 or not value.event_id is String or not UuidV4Script.is_valid(value.event_id):
		errors.append("invalid_identity")
	if not value.profile_id is String or value.profile_id.is_empty() or not value.device_id is String or value.device_id.is_empty() or not value.session_id is String or value.session_id.is_empty():
		errors.append("invalid_context")
	if not _is_integer(value.sequence) or value.sequence < 1:
		errors.append("invalid_sequence")
	if not value.client_timestamp is String or value.client_timestamp.length() != 20 or not value.client_timestamp.ends_with("Z"):
		errors.append("invalid_timestamp")
	if not value.event_type is String or not value.event_type in TYPES:
		errors.append("invalid_type")
	if value.event_type == "answer_submitted":
		for key in ANSWER:
			if not value.has(key): errors.append("missing_%s" % key)
		if not errors.is_empty(): return errors
		if not value.activity_id is String or not value.content_version is String or not value.generator_id is String or not value.band_id is String or not _is_integer(value.question_seed) or not value.resolved_parameters is Dictionary or not _is_integer(value.submitted_answer) or not _is_integer(value.correct_answer) or not value.correctness is bool or not _is_integer(value.response_duration_ms) or value.response_duration_ms < 0 or not _is_integer(value.hints) or value.hints < 0 or not _is_integer(value.health_delta) or not _is_integer(value.combo) or value.combo < 0 or not value.reward_delta is Dictionary:
			errors.append("invalid_answer_fields")
	return errors

static func _is_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))
