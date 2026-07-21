extends Node

const FILE_NAME := "profiles.json"
const MAX_NOW_UNIX := 9007199254740961
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ProfileRecordScript = preload("res://src/profiles/profile_record.gd")
const PinVerifierScript = preload("res://src/profiles/pin_verifier.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")

signal profiles_changed
signal selection_changed

var _store: AtomicJsonStoreScript
var _profiles: Array[Dictionary] = []
var _selected_profile_id := ""

func _init(store: AtomicJsonStoreScript = null) -> void:
	_store = store if store != null else AtomicJsonStoreScript.new("user://.")
	_load_index()

func create_profile(nickname: Variant, avatar_id: Variant, pin: Variant) -> Dictionary:
	var normalized_nickname := ProfileRecordScript.normalize_nickname(nickname)
	if normalized_nickname.is_empty():
		return {"ok": false, "error": "invalid_nickname"}
	for profile in _profiles:
		if profile.nickname == normalized_nickname:
			return {"ok": false, "error": "duplicate_nickname"}
	if not ProfileRecordScript.is_valid_avatar(avatar_id):
		return {"ok": false, "error": "invalid_avatar"}
	if not PinVerifierScript.is_valid(pin):
		return {"ok": false, "error": "invalid_pin"}
	var pin_data := PinVerifierScript.create(pin)
	var profile := ProfileRecordScript.create(
		UuidV4Script.generate(), normalized_nickname, avatar_id, pin_data, int(Time.get_unix_time_from_system())
	)
	var candidate := _profiles.duplicate(true)
	candidate.append(profile)
	if _save_index(candidate, _selected_profile_id) != OK:
		return {"ok": false, "error": "save_failed"}
	_profiles = candidate
	profiles_changed.emit()
	return {"ok": true, "profile": _public_profile(profile)}

func verify_and_select(profile_id: Variant, pin: Variant, now_unix: Variant) -> Dictionary:
	if not profile_id is String or not now_unix is int or now_unix < 0 or now_unix > MAX_NOW_UNIX:
		return {"ok": false, "error": "invalid_request"}
	var index := _profile_index(profile_id)
	if index < 0:
		return {"ok": false, "error": "profile_not_found"}
	var profile := _profiles[index]
	if now_unix < profile.locked_until:
		return {"ok": false, "error": "pin_locked"}
	if not PinVerifierScript.verify(pin, profile.pin_salt, profile.pin_verifier):
		var failed_candidate := _profiles.duplicate(true)
		var failed_profile: Dictionary = failed_candidate[index]
		failed_profile.failed_attempts += 1
		if failed_profile.failed_attempts >= 5:
			failed_profile.failed_attempts = 5
			failed_profile.locked_until = now_unix + 30
		if _save_index(failed_candidate, _selected_profile_id) != OK:
			return {"ok": false, "error": "save_failed"}
		_profiles = failed_candidate
		return {"ok": false, "error": "invalid_pin"}

	var selected_candidate := _profiles.duplicate(true)
	var selected_record: Dictionary = selected_candidate[index]
	selected_record.failed_attempts = 0
	selected_record.locked_until = 0
	if _save_index(selected_candidate, profile_id) != OK:
		return {"ok": false, "error": "save_failed"}
	_profiles = selected_candidate
	_selected_profile_id = profile_id
	selection_changed.emit()
	return {"ok": true, "profile": _public_profile(selected_record)}

func update_settings(profile_id: Variant, patch: Variant) -> Error:
	if not profile_id is String:
		return ERR_INVALID_PARAMETER
	var index := _profile_index(profile_id)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	var candidate := _profiles.duplicate(true)
	var updated_settings := ProfileRecordScript.apply_settings_patch(candidate[index].settings, patch)
	if updated_settings.is_empty():
		return ERR_INVALID_PARAMETER
	candidate[index].settings = updated_settings
	var save_error := _save_index(candidate, _selected_profile_id)
	if save_error != OK:
		return save_error
	_profiles = candidate
	profiles_changed.emit()
	return OK

func selected_profile() -> Dictionary:
	var index := _profile_index(_selected_profile_id)
	return _public_profile(_profiles[index]) if index >= 0 else {}

func list_profiles() -> Array[Dictionary]:
	var public_profiles: Array[Dictionary] = []
	for profile in _profiles:
		public_profiles.append(_public_profile(profile))
	return public_profiles

func get_profile(profile_id: Variant) -> Dictionary:
	if not profile_id is String:
		return {}
	var index := _profile_index(profile_id)
	return _public_profile(_profiles[index]) if index >= 0 else {}

func read_index_for_test() -> Dictionary:
	return _index_dictionary(_profiles, _selected_profile_id)

func _load_index() -> void:
	var loaded: Dictionary = _store.load(FILE_NAME)
	if not loaded.get("ok", false) or not loaded.get("value", null) is Dictionary:
		return
	var index: Dictionary = loaded.value
	if index.size() != 3 or not index.has("schema_version") or not index.has("selected_profile_id") or not index.has("profiles"):
		return
	if not (index.schema_version is int or index.schema_version is float) or index.schema_version != 1:
		return
	var selected: Variant = index.selected_profile_id
	if not selected is String:
		return
	var records: Variant = index.get("profiles", [])
	if not records is Array:
		return
	var loaded_profiles: Array[Dictionary] = []
	for value in records:
		var profile := ProfileRecordScript.from_dictionary(value)
		if profile.is_empty() or _contains_profile(loaded_profiles, profile.profile_id):
			return
		loaded_profiles.append(profile)
	if _contains_profile(loaded_profiles, selected):
		_selected_profile_id = selected
	_profiles = loaded_profiles

func _save_index(profiles: Array[Dictionary], selected_profile_id: String) -> Error:
	return _store.save(FILE_NAME, _index_dictionary(profiles, selected_profile_id))

func _index_dictionary(profiles: Array[Dictionary], selected_profile_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"selected_profile_id": selected_profile_id,
		"profiles": profiles.duplicate(true),
	}

func _profile_index(profile_id: String) -> int:
	for index in _profiles.size():
		if _profiles[index].profile_id == profile_id:
			return index
	return -1

func _contains_profile(profiles: Array[Dictionary], profile_id: String) -> bool:
	for profile in profiles:
		if profile.profile_id == profile_id:
			return true
	return false

func _public_profile(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return {}
	return {
		"profile_id": profile.profile_id,
		"nickname": profile.nickname,
		"avatar_id": profile.avatar_id,
		"settings": profile.settings.duplicate(true),
		"created_at": profile.created_at,
	}
