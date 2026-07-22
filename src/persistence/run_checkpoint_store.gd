class_name RunCheckpointStore
extends RefCounted

const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")

const FILE_NAME := "run_checkpoint.json"
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_FILE_BYTES := 1_048_576
const CHECKPOINT_KEYS := [
	"schema_version",
	"profile_id",
	"session_id",
	"content_version",
	"activity_id",
	"run_state",
	"current_question",
	"last_event_sequence",
]
const RUN_STATE_KEYS := [
	"revision",
	"session_id",
	"activity_id",
	"content_version",
	"stage_id",
	"health",
	"score",
	"combo",
	"question_index",
	"current_question",
	"current_seed",
	"awaiting_answer",
	"boss_state",
	"earned_rewards",
	"paused",
	"timer_enabled",
	"timer_started_at_ms",
	"timer_remaining_ms",
	"completion_reason",
	"status",
]
const LEGACY_QUESTION_KEYS := [
	"question_id",
	"activity_id",
	"content_version",
	"generator_id",
	"band_id",
	"seed",
	"resolved_parameters",
	"prompt_key",
	"correct_answer",
	"answer_layout",
	"manipulative",
]
const V1_QUESTION_KEYS := [
	"contract_version",
	"activity_id",
	"content_version",
	"generator_id",
	"band_id",
	"seed",
	"resolved_parameters",
	"prompt",
	"correct_answer",
	"answer_layout",
	"manipulative",
]

var _base_path := "user://profiles"

func _init(base_path: String = "user://profiles") -> void:
	_base_path = base_path.rstrip("/")

func save(checkpoint: Dictionary) -> Dictionary:
	if not _is_valid_checkpoint(checkpoint):
		return {"ok": false, "error": "invalid_checkpoint"}
	var profile_id: String = checkpoint.profile_id
	var store := AtomicJsonStoreScript.new(_profile_path(profile_id))
	var error := store.save(FILE_NAME, checkpoint.duplicate(true))
	if error != OK:
		return {"ok": false, "error": "checkpoint_save_failed", "code": error}
	return {"ok": true}

func load(profile_id: String, expected_content_version: String = "") -> Dictionary:
	if not UuidV4Script.is_valid(profile_id):
		return {"ok": false, "error": "invalid_profile_id"}
	var final_path := _file_path(profile_id)
	var backup_path := "%s.bak" % final_path
	var readable_path := final_path if _file_exists(final_path) else backup_path
	if _file_exists(readable_path):
		var size_check := _file_size_is_safe(readable_path)
		if not size_check.get("ok", false):
			if size_check.get("error") == "checkpoint_too_large":
				return _invalid_checkpoint(profile_id, readable_path)
			return size_check
	var store := AtomicJsonStoreScript.new(_profile_path(profile_id))
	var loaded: Dictionary = store.load(FILE_NAME)
	if not loaded.get("ok", false):
		return loaded.duplicate(true)
	var value: Variant = loaded.get("value")
	if not value is Dictionary or not _is_valid_checkpoint(value) or value.profile_id != profile_id:
		return _invalid_checkpoint(profile_id)
	var normalized: Variant = _normalize_json_numbers(value)
	if not normalized is Dictionary or not _is_valid_checkpoint(normalized):
		return _invalid_checkpoint(profile_id)
	var checkpoint: Dictionary = normalized
	if not expected_content_version.is_empty() and checkpoint.content_version != expected_content_version:
		return {"ok": false, "error": "content_version_mismatch"}
	return {"ok": true, "checkpoint": checkpoint}

func delete(profile_id: String) -> Dictionary:
	if not UuidV4Script.is_valid(profile_id):
		return {"ok": false, "error": "invalid_profile_id"}
	var final_path := _file_path(profile_id)
	var temporary_path := "%s.tmp" % final_path
	var backup_path := "%s.bak" % final_path
	var tombstone_path := "%s.delete" % final_path
	if _file_exists(tombstone_path) and _remove_path(tombstone_path) != OK:
		return {"ok": false, "error": "checkpoint_delete_failed"}
	var source_path := final_path if _file_exists(final_path) else backup_path
	if _file_exists(source_path) and _rename_path(source_path, tombstone_path) != OK:
		return {"ok": false, "error": "checkpoint_delete_failed"}
	for stale_path in [temporary_path, backup_path]:
		if _file_exists(stale_path) and _remove_path(stale_path) != OK:
			return {"ok": false, "error": "checkpoint_delete_failed"}
	if _file_exists(tombstone_path) and _remove_path(tombstone_path) != OK:
		return {"ok": false, "error": "checkpoint_delete_failed"}
	return {"ok": true}

func quarantine(profile_id: String) -> Dictionary:
	if not UuidV4Script.is_valid(profile_id):
		return {"ok": false, "error": "invalid_profile_id"}
	var final_path := _file_path(profile_id)
	var source_path := final_path if _file_exists(final_path) else "%s.bak" % final_path
	if not _file_exists(source_path):
		return {"ok": false, "error": "not_found"}
	var quarantine_path := "%s.corrupt" % _file_path(profile_id)
	if _file_exists(quarantine_path) and _remove_path(quarantine_path) != OK:
		return {"ok": false, "error": "quarantine_failed", "quarantine_path": quarantine_path}
	if _rename_path(source_path, quarantine_path) != OK:
		return {"ok": false, "error": "quarantine_failed", "quarantine_path": quarantine_path}
	return {"ok": true, "quarantine_path": quarantine_path}

func _invalid_checkpoint(profile_id: String, source_path: String = "") -> Dictionary:
	var quarantined: Dictionary
	if source_path.is_empty() or source_path == _file_path(profile_id) or source_path == "%s.bak" % _file_path(profile_id):
		quarantined = quarantine(profile_id)
	else:
		return {"ok": false, "error": "quarantine_failed"}
	if not quarantined.get("ok", false):
		return quarantined
	var quarantine_path: String = quarantined.quarantine_path
	return {"ok": false, "error": "invalid_checkpoint", "quarantine_path": quarantine_path}

func _file_size_is_safe(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "read_failed"}
	var length := file.get_length()
	file.close()
	if length > MAX_FILE_BYTES:
		return {"ok": false, "error": "checkpoint_too_large"}
	return {"ok": true}

func _is_valid_checkpoint(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, CHECKPOINT_KEYS):
		return false
	var checkpoint: Dictionary = value
	if (
		not _is_integer(checkpoint.schema_version)
		or int(checkpoint.schema_version) != 1
		or not checkpoint.profile_id is String
		or not UuidV4Script.is_valid(checkpoint.profile_id)
		or not checkpoint.session_id is String
		or not UuidV4Script.is_valid(checkpoint.session_id)
		or not _is_nonempty_string(checkpoint.content_version)
		or not _is_nonempty_string(checkpoint.activity_id)
		or not _is_nonnegative_integer(checkpoint.last_event_sequence)
		or checkpoint.last_event_sequence <= 0
		or not _is_valid_question(checkpoint.current_question, checkpoint.activity_id, checkpoint.content_version)
		or not _is_valid_run_state(checkpoint.run_state, checkpoint)
	):
		return false
	return true

func _is_valid_run_state(value: Variant, checkpoint: Dictionary) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, RUN_STATE_KEYS):
		return false
	var state: Dictionary = value
	if (
		not _is_nonnegative_integer(state.revision)
		or state.session_id != checkpoint.session_id
		or state.activity_id != checkpoint.activity_id
		or state.content_version != checkpoint.content_version
		or not _is_nonempty_string(state.stage_id)
		or not _is_nonnegative_integer(state.health)
		or not _is_nonnegative_integer(state.score)
		or not _is_nonnegative_integer(state.combo)
		or not _is_nonnegative_integer(state.question_index)
		or not _is_nonnegative_integer(state.current_seed)
		or state.current_seed != checkpoint.current_question.seed
		or not state.awaiting_answer is bool
		or not state.awaiting_answer
		or not state.boss_state is bool
		or not state.paused is bool
		or not state.timer_enabled is bool
		or not _is_nonnegative_integer(state.timer_started_at_ms)
		or not _is_nonnegative_integer(state.timer_remaining_ms)
		or state.completion_reason != ""
		or state.status != "running"
		or not _is_reward_map(state.earned_rewards)
		or not _dictionaries_equal(state.current_question, checkpoint.current_question)
	):
		return false
	if not state.timer_enabled and int(state.timer_remaining_ms) != 0:
		return false
	return true

func _is_valid_question(value: Variant, activity_id: String, content_version: String) -> bool:
	if not value is Dictionary:
		return false
	var question: Dictionary = value
	if question.has("contract_version"):
		return _is_valid_v1_question(question, activity_id, content_version)
	if not _has_required_keys(question, LEGACY_QUESTION_KEYS):
		return false
	if (
		not _is_nonempty_string(question.question_id)
		or question.activity_id != activity_id
		or question.content_version != content_version
		or not _is_nonempty_string(question.generator_id)
		or not _is_nonempty_string(question.band_id)
		or not _is_nonnegative_integer(question.seed)
		or not _is_nonempty_string(question.prompt_key)
		or not _is_nonempty_string(question.answer_layout)
		or not question.resolved_parameters is Dictionary
		or not question.manipulative is Dictionary
		or not _is_json_value(question, 0)
	):
		return false
	return true

func _is_valid_v1_question(question: Dictionary, activity_id: String, content_version: String) -> bool:
	if not _has_exact_keys(question, V1_QUESTION_KEYS):
		return false
	var prompt: Variant = question.get("prompt")
	var answer_layout: Variant = question.get("answer_layout")
	var manipulative: Variant = question.get("manipulative")
	if (
		not _is_integer(question.get("contract_version"))
		or int(question.get("contract_version")) != 1
		or question.get("activity_id") != activity_id
		or question.get("content_version") != content_version
		or not _is_nonempty_string(question.get("generator_id"))
		or not _is_nonempty_string(question.get("band_id"))
		or not _is_nonnegative_integer(question.get("seed"))
		or not question.get("resolved_parameters") is Dictionary
		or not prompt is Dictionary
		or not _has_exact_keys(prompt, ["key", "args"])
		or not _is_nonempty_string(prompt.get("key"))
		or not prompt.get("args") is Dictionary
		or not _is_valid_v1_answer(question.get("correct_answer"))
		or not answer_layout is Dictionary
		or not _has_allowed_keys(answer_layout, ["id"], ["options"])
		or not _is_nonempty_string(answer_layout.get("id"))
		or (answer_layout.has("options") and not answer_layout.get("options") is Dictionary)
		or not manipulative is Dictionary
		or not _has_exact_keys(manipulative, ["id", "config", "initial_state"])
		or not _is_nonempty_string(manipulative.get("id"))
		or not manipulative.get("config") is Dictionary
		or not manipulative.get("initial_state") is Dictionary
		or not _is_json_value(question, 0)
	):
		return false
	return true

func _is_valid_v1_answer(value: Variant) -> bool:
	if not value is Dictionary or not _is_nonempty_string(value.get("kind")):
		return false
	var answer: Dictionary = value
	if answer.kind == "integer":
		return _has_exact_keys(answer, ["kind", "value"]) and _is_integer(answer.get("value"))
	if answer.kind != "integer_list" or not _has_exact_keys(answer, ["kind", "values", "order_matters"]):
		return false
	var values: Variant = answer.get("values")
	if not values is Array or values.is_empty() or values.size() > 64 or not answer.get("order_matters") is bool:
		return false
	for item in values:
		if not _is_integer(item):
			return false
	return true

func _is_json_value(value: Variant, depth: int) -> bool:
	if depth > 8:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	if value is float:
		return is_finite(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	if value is Array:
		if value.size() > 256:
			return false
		for item in value:
			if not _is_json_value(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 256:
			return false
		for key in value:
			if not _is_nonempty_string(key) or not _is_json_value(value[key], depth + 1):
				return false
		return true
	return false

func _is_reward_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not _is_nonempty_string(key) or not _is_nonnegative_integer(value[key]):
			return false
	return true

func _dictionaries_equal(left: Dictionary, right: Dictionary) -> bool:
	var normalized_left: Variant = JSON.parse_string(JSON.stringify(left))
	var normalized_right: Variant = JSON.parse_string(JSON.stringify(right))
	return normalized_left is Dictionary and normalized_right is Dictionary and normalized_left == normalized_right

func _normalize_json_numbers(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER:
		return int(value)
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_json_numbers(item))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary := {}
		for key in value:
			normalized_dictionary[key] = _normalize_json_numbers(value[key])
		return normalized_dictionary
	return value

func _has_allowed_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	if not _has_required_keys(value, required):
		return false
	for key in value:
		if key not in required and key not in optional:
			return false
	return true

func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

func _has_required_keys(value: Dictionary, expected: Array) -> bool:
	for key in expected:
		if not value.has(key):
			return false
	return true

func _is_nonempty_string(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer(value) and value >= 0

func _is_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value == floor(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER

func _profile_path(profile_id: String) -> String:
	return "%s/%s" % [_base_path, profile_id]

func _file_path(profile_id: String) -> String:
	return "%s/%s" % [_profile_path(profile_id), FILE_NAME]

func _file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func _rename_path(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))

func _remove_path(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
