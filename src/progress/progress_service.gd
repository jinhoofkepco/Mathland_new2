class_name ProgressService
extends Node

signal progress_changed(snapshot: Dictionary)

const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const ProgressReducerScript = preload("res://src/progress/progress_reducer.gd")

const SNAPSHOT_FILE := "snapshot.json"
const SNAPSHOT_CORRUPT_SUFFIX := ".corrupt"
const SNAPSHOT_CORRUPT_TEMP_SUFFIX := ".corrupt.tmp"
const SNAPSHOT_CORRUPT_BACKUP_SUFFIX := ".corrupt.bak"
const MAX_SAFE_INTEGER := 9007199254740991
const SNAPSHOT_KEYS := [
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

var _store_provider: Variant
var _store_profiles_by_path := {}
var _store_profiles_by_instance := {}
var _store: AtomicJsonStoreScript
var _journal: Variant
var _profile_id := ""
var _state: Dictionary = {}
var _loaded := false

func _init(store_provider: Variant = null) -> void:
	_store_provider = store_provider

func load_profile(profile_id: String, journal: Variant) -> Dictionary:
	_clear_loaded_state()
	if profile_id.is_empty() or journal == null or not journal.has_method("replay"):
		return {"ok": false, "error": "invalid_request"}
	var resolved_store := _store_for_profile(profile_id)
	if not resolved_store.get("ok", false):
		return resolved_store
	var target_store: AtomicJsonStoreScript = resolved_store.store

	var recovered_quarantine := _recover_interrupted_snapshot_quarantine(target_store)
	if not recovered_quarantine.get("ok", false):
		return recovered_quarantine
	var candidate := ProgressReducerScript.initial_state(profile_id)
	var durable_sequence := 0
	var quarantined_snapshot: bool = recovered_quarantine.get("recovered", false)
	var loaded_snapshot: Dictionary = target_store.load(SNAPSHOT_FILE)
	if loaded_snapshot.get("ok", false):
		if _is_valid_snapshot(loaded_snapshot.get("value", null), profile_id):
			candidate = _normalized_snapshot(loaded_snapshot.value)
			durable_sequence = int(candidate.last_sequence)
		else:
			var quarantined := _quarantine_snapshot(target_store)
			if not quarantined.get("ok", false):
				return quarantined
			quarantined_snapshot = true
	else:
		var snapshot_error: String = loaded_snapshot.get("error", "snapshot_load_failed")
		if snapshot_error == "invalid_json":
			quarantined_snapshot = true
		elif snapshot_error != "not_found":
			return loaded_snapshot.duplicate(true)

	var replayed: Variant = journal.replay()
	if (
		not replayed is Dictionary
		or not replayed.has("ok")
		or not replayed.ok is bool
		or (replayed.has("quarantined_tail") and not replayed.quarantined_tail is bool)
	):
		return {"ok": false, "error": "invalid_replay_result"}
	if not replayed.ok:
		if not replayed.get("error", null) is String or replayed.error.is_empty():
			return {"ok": false, "error": "invalid_replay_result"}
		return replayed.duplicate(true)
	var compacted_through := _journal_compacted_through(journal)
	if compacted_through > int(candidate.last_sequence):
		return {"ok": false, "error": "snapshot_behind_compaction"}
	var validated := _validate_replay(replayed, profile_id, compacted_through)
	if not validated.get("ok", false):
		return validated

	var highest_sequence := compacted_through
	for event in validated.events:
		highest_sequence = maxi(highest_sequence, int(event.sequence))
		if highest_sequence <= int(candidate.last_sequence):
			continue
		if highest_sequence != int(candidate.last_sequence) + 1:
			return {
				"ok": false,
				"error": "invalid_sequence",
				"sequence": highest_sequence,
			}
		var next := ProgressReducerScript.apply(candidate, event)
		if int(next.get("last_sequence", -1)) != highest_sequence:
			return {"ok": false, "error": "invalid_event", "sequence": highest_sequence}
		candidate = next
	if int(candidate.last_sequence) > highest_sequence:
		return {"ok": false, "error": "snapshot_ahead"}
	if int(candidate.last_sequence) != durable_sequence:
		var recovery_save_error := target_store.save(SNAPSHOT_FILE, candidate)
		if recovery_save_error != OK:
			return {
				"ok": false,
				"error": "snapshot_recovery_save_failed",
				"code": recovery_save_error,
			}

	_store = target_store
	_journal = journal
	_profile_id = profile_id
	_state = candidate
	_loaded = true
	return {
		"ok": true,
		"snapshot": snapshot(),
		"quarantined_snapshot": quarantined_snapshot,
		"quarantined_tail": replayed.get("quarantined_tail", false),
	}

func _clear_loaded_state() -> void:
	_store = null
	_journal = null
	_profile_id = ""
	_state = {}
	_loaded = false

func _store_for_profile(profile_id: String) -> Dictionary:
	var target_store: AtomicJsonStoreScript
	if _store_provider == null:
		target_store = AtomicJsonStoreScript.new("user://profiles/%s" % profile_id)
	elif _store_provider is AtomicJsonStoreScript:
		target_store = _store_provider
	else:
		if not _store_provider is Object or not _store_provider.has_method("create_store"):
			return {"ok": false, "error": "invalid_store_factory"}
		var created_store: Variant = _store_provider.call("create_store", profile_id)
		if not created_store is AtomicJsonStoreScript:
			return {"ok": false, "error": "invalid_store_factory"}
		target_store = created_store
	return _bind_store_to_profile(target_store, profile_id)

func _bind_store_to_profile(store: AtomicJsonStoreScript, profile_id: String) -> Dictionary:
	var snapshot_path := ProjectSettings.globalize_path(store._path_for(SNAPSHOT_FILE)).simplify_path()
	var instance_id := store.get_instance_id()
	var path_profile: String = _store_profiles_by_path.get(snapshot_path, "")
	var instance_profile: String = _store_profiles_by_instance.get(instance_id, "")
	if (
		(not path_profile.is_empty() and path_profile != profile_id)
		or (not instance_profile.is_empty() and instance_profile != profile_id)
	):
		return {"ok": false, "error": "store_profile_mismatch"}
	_store_profiles_by_path[snapshot_path] = profile_id
	_store_profiles_by_instance[instance_id] = profile_id
	return {"ok": true, "store": store}

func commit(event: Dictionary) -> Error:
	if not _loaded:
		return ERR_UNCONFIGURED
	if not LearningEventV1Script.validate(event).is_empty():
		return ERR_INVALID_DATA
	if event.profile_id != _profile_id:
		return ERR_INVALID_PARAMETER
	var sequence := int(event.sequence)
	var last_sequence := int(_state.last_sequence)
	if sequence <= last_sequence:
		return ERR_ALREADY_EXISTS
	if sequence != last_sequence + 1:
		return ERR_INVALID_DATA

	var replayed: Variant = _journal.replay()
	if (
		not replayed is Dictionary
		or not replayed.has("ok")
		or not replayed.ok is bool
		or not replayed.ok
		or (replayed.has("quarantined_tail") and not replayed.quarantined_tail is bool)
	):
		return FAILED
	var validated := _validate_replay(replayed, _profile_id, _journal_compacted_through(_journal))
	if not validated.get("ok", false):
		return ERR_INVALID_DATA
	var journaled_event: Dictionary = {}
	for replayed_event in validated.events:
		if int(replayed_event.sequence) == sequence:
			journaled_event = replayed_event
			break
	if journaled_event.is_empty():
		return ERR_DOES_NOT_EXIST
	if not _events_equal(journaled_event, event):
		return ERR_INVALID_DATA

	var candidate := ProgressReducerScript.apply(_state, event)
	if int(candidate.get("last_sequence", -1)) != sequence or not _is_valid_snapshot(candidate, _profile_id):
		return ERR_INVALID_DATA
	var save_error: Error = _store.save(SNAPSHOT_FILE, candidate)
	if save_error != OK:
		return save_error
	_state = candidate
	progress_changed.emit(_state.duplicate(true))
	return OK

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func _validate_replay(replayed: Dictionary, profile_id: String, compacted_sequence: int = 0) -> Dictionary:
	var events_value: Variant = replayed.get("events", null)
	if not events_value is Array:
		return {"ok": false, "error": "invalid_replay_result"}
	var events: Array = events_value
	var expected_sequence := -1
	for event in events:
		if not event is Dictionary or not LearningEventV1Script.validate(event).is_empty():
			return {"ok": false, "error": "invalid_record", "sequence": maxi(expected_sequence, 1)}
		if event.profile_id != profile_id:
			return {"ok": false, "error": "scope_mismatch", "sequence": int(event.sequence)}
		if expected_sequence < 0:
			if int(event.sequence) != 1 and int(event.sequence) != compacted_sequence + 1:
				return {
					"ok": false,
					"error": "invalid_sequence",
					"sequence": int(event.sequence),
				}
			expected_sequence = int(event.sequence)
		if int(event.sequence) != expected_sequence:
			return {
				"ok": false,
				"error": "invalid_sequence",
				"sequence": int(event.sequence),
			}
		expected_sequence += 1
	return {"ok": true, "events": events}

func _journal_compacted_through(journal: Variant) -> int:
	if journal == null or not journal.has_method("compacted_through"):
		return 0
	var value: Variant = journal.compacted_through()
	return int(value) if _is_nonnegative_safe_integer(value) else 0

func _events_equal(left: Dictionary, right: Dictionary) -> bool:
	var normalized_left: Variant = JSON.parse_string(JSON.stringify(left))
	var normalized_right: Variant = JSON.parse_string(JSON.stringify(right))
	return (
		normalized_left is Dictionary
		and normalized_right is Dictionary
		and JSON.stringify(normalized_left) == JSON.stringify(normalized_right)
	)

func _is_valid_snapshot(value: Variant, profile_id: String) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, SNAPSHOT_KEYS):
		return false
	var state: Dictionary = value
	if (
		not _is_safe_integer(state.schema_version)
		or int(state.schema_version) != 1
		or not state.profile_id is String
		or state.profile_id != profile_id
		or not _is_nonnegative_safe_integer(state.last_sequence)
		or not _is_nonnegative_safe_integer(state.apples)
		or not _is_nonnegative_safe_integer(state.pending_review)
		or not state.inventory is Dictionary
		or not state.collections is Array
		or not state.coupons is Array
		or not state.activity_progress is Dictionary
		or not state.run_totals is Dictionary
	):
		return false
	if state.inventory.has("apples") or not _is_count_map(state.inventory, true):
		return false
	if not _is_unique_string_array(state.collections) or not _is_unique_string_array(state.coupons):
		return false
	if not _has_exact_keys(state.run_totals, RUN_TOTAL_KEYS):
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

func _normalized_snapshot(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	normalized.schema_version = int(normalized.schema_version)
	normalized.last_sequence = int(normalized.last_sequence)
	normalized.apples = int(normalized.apples)
	normalized.pending_review = int(normalized.pending_review)
	for reward_name in normalized.inventory:
		normalized.inventory[reward_name] = int(normalized.inventory[reward_name])
	for total_key in RUN_TOTAL_KEYS:
		normalized.run_totals[total_key] = int(normalized.run_totals[total_key])
	for activity_id in normalized.activity_progress:
		var activity: Dictionary = normalized.activity_progress[activity_id]
		activity.attempts = int(activity.attempts)
		activity.correct = int(activity.correct)
		for error_key in activity.repeated_errors:
			activity.repeated_errors[error_key] = int(activity.repeated_errors[error_key])
		normalized.activity_progress[activity_id] = activity
	return normalized

func _quarantine_snapshot(store: AtomicJsonStoreScript) -> Dictionary:
	var snapshot_path: String = store._path_for(SNAPSHOT_FILE)
	var quarantine_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_SUFFIX]
	var temporary_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_TEMP_SUFFIX]
	var backup_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_BACKUP_SUFFIX]
	if (
		not _snapshot_file_exists(snapshot_path)
		or _snapshot_file_exists(temporary_path)
		or _snapshot_file_exists(backup_path)
	):
		return _quarantine_failure(quarantine_path)
	if _rename_snapshot_path(snapshot_path, temporary_path) != OK:
		return _quarantine_failure(quarantine_path)
	if _promote_snapshot_quarantine(temporary_path, quarantine_path, backup_path) != OK:
		return _quarantine_failure(quarantine_path)
	return {"ok": true, "quarantine_path": quarantine_path}

func _recover_interrupted_snapshot_quarantine(store: AtomicJsonStoreScript) -> Dictionary:
	var snapshot_path: String = store._path_for(SNAPSHOT_FILE)
	var quarantine_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_SUFFIX]
	var temporary_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_TEMP_SUFFIX]
	var backup_path := "%s%s" % [snapshot_path, SNAPSHOT_CORRUPT_BACKUP_SUFFIX]
	var has_quarantine := _snapshot_file_exists(quarantine_path)
	var has_temporary := _snapshot_file_exists(temporary_path)
	var has_backup := _snapshot_file_exists(backup_path)
	if has_backup:
		if has_quarantine:
			if has_temporary or _remove_snapshot_path(backup_path) != OK:
				return _quarantine_failure(quarantine_path)
			return {"ok": true, "recovered": true, "quarantine_path": quarantine_path}
		if has_temporary:
			if _rename_snapshot_path(temporary_path, quarantine_path) != OK:
				if _rename_snapshot_path(backup_path, quarantine_path) != OK:
					return _quarantine_failure(quarantine_path)
				return _quarantine_failure(quarantine_path)
			if _remove_snapshot_path(backup_path) != OK:
				return _quarantine_failure(quarantine_path)
			return {"ok": true, "recovered": true, "quarantine_path": quarantine_path}
		if _rename_snapshot_path(backup_path, quarantine_path) != OK:
			return _quarantine_failure(quarantine_path)
		return {"ok": true, "recovered": true, "quarantine_path": quarantine_path}
	if has_temporary:
		if _promote_snapshot_quarantine(temporary_path, quarantine_path, backup_path) != OK:
			return _quarantine_failure(quarantine_path)
		return {"ok": true, "recovered": true, "quarantine_path": quarantine_path}
	return {"ok": true, "recovered": false, "quarantine_path": quarantine_path}

func _promote_snapshot_quarantine(temporary_path: String, quarantine_path: String, backup_path: String) -> Error:
	if _snapshot_file_exists(backup_path):
		return FAILED
	if _snapshot_file_exists(quarantine_path):
		if _rename_snapshot_path(quarantine_path, backup_path) != OK:
			return FAILED
	if _rename_snapshot_path(temporary_path, quarantine_path) != OK:
		if _snapshot_file_exists(backup_path) and _rename_snapshot_path(backup_path, quarantine_path) != OK:
			return FAILED
		return FAILED
	if _snapshot_file_exists(backup_path) and _remove_snapshot_path(backup_path) != OK:
		return FAILED
	return OK

func _quarantine_failure(quarantine_path: String) -> Dictionary:
	return {"ok": false, "error": "quarantine_failed", "quarantine_path": quarantine_path}

func _snapshot_file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func _rename_snapshot_path(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path)
	)

func _remove_snapshot_path(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _has_exact_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key in expected_keys:
		if not value.has(key):
			return false
	return true

func _is_count_map(value: Dictionary, allow_zero: bool) -> bool:
	for key in value:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(value[key]):
			return false
		if not allow_zero and int(value[key]) == 0:
			return false
	return true

func _is_unique_string_array(value: Array) -> bool:
	var seen := {}
	for item in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true

func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and value >= 0

func _is_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return (
		value is float
		and is_finite(value)
		and value >= -MAX_SAFE_INTEGER
		and value <= MAX_SAFE_INTEGER
		and value == floor(value)
	)
