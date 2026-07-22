extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/profiles"
const AtomicJsonStore = preload("res://src/persistence/atomic_json_store.gd")
const ProfileService = preload("res://src/profiles/profile_service.gd")
const ProfileRecord = preload("res://src/profiles/profile_record.gd")

class FailingSaveStore extends AtomicJsonStore:
	func _init() -> void:
		super(BASE_PATH)

	func save(_path: String, _value: Variant) -> Error:
		return ERR_CANT_CREATE

class ToggleSaveStore extends AtomicJsonStore:
	var fail_saves := false

	func save(path: String, value: Variant) -> Error:
		if fail_saves:
			return ERR_CANT_CREATE
		return super(path, value)

class MalformedStore extends AtomicJsonStore:
	var load_calls := 0
	var save_calls := 0

	func _init() -> void:
		super(BASE_PATH)

	func load(_path: String) -> Dictionary:
		load_calls += 1
		return {"ok": true, "value": "not_an_index"}

	func save(_path: String, _value: Variant) -> Error:
		save_calls += 1
		return ERR_CANT_CREATE

func run(_tree: SceneTree) -> void:
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_profiles_are_isolated_and_pin_is_not_plaintext()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_invalid_profile_inputs_are_rejected()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_normalized_duplicate_nicknames_and_public_list()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_persisted_invalid_nicknames_and_integers_are_rejected()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_persisted_unknown_fields_are_stripped_and_index_shape_is_validated()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_malformed_store_response_does_not_fallback()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_lock_state_persists_and_is_isolated()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_settings_patch_is_validated()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_save_failures_do_not_mutate_service_state()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_settings_and_selection_save_failures_rollback()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_failed_pin_save_failure_rolls_back_security_state()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])

func _test_profiles_are_isolated_and_pin_is_not_plaintext() -> void:
	var service := ProfileService.new(AtomicJsonStore.new(BASE_PATH))
	var a := service.create_profile("하늘", "moa_sky", "1234")
	var b := service.create_profile("바다", "moa_mint", "5678")
	assert_true(a.ok and b.ok)
	assert_ne(a.profile.profile_id, b.profile.profile_id)
	assert_eq(service.update_settings(a.profile.profile_id, {"reduced_motion": true}), OK)
	assert_false(service.get_profile(b.profile.profile_id).settings.reduced_motion)
	var raw := service.read_index_for_test()
	assert_false(JSON.stringify(raw).contains("1234"), "plaintext PIN must never be stored")
	assert_false(JSON.stringify(raw).contains("5678"), "plaintext PIN must never be stored")
	assert_true(raw.profiles[0].has("pin_salt"))
	assert_true(raw.profiles[0].has("pin_verifier"))
	service.free()

func _test_invalid_profile_inputs_are_rejected() -> void:
	var service := ProfileService.new(AtomicJsonStore.new(BASE_PATH))
	assert_eq(service.create_profile("   ", "moa_sky", "1234").error, "invalid_nickname")
	assert_eq(service.create_profile("12345678901234567", "moa_sky", "1234").error, "invalid_nickname")
	assert_eq(service.create_profile("한글😀", "not_an_avatar", "1234").error, "invalid_avatar")
	assert_eq(service.create_profile("모아", "moa_coral", "12가4").error, "invalid_pin")
	service.free()

func _test_normalized_duplicate_nicknames_and_public_list() -> void:
	var service := ProfileService.new(AtomicJsonStore.new(BASE_PATH))
	var first := service.create_profile("  모아  ", "moa_mint", "1234")
	assert_true(first.ok)
	assert_eq(service.create_profile("모아", "moa_sky", "5678").error, "duplicate_nickname")
	assert_true(service.create_profile("모아A", "moa_sky", "5678").ok)
	var listed := service.list_profiles()
	assert_eq(listed.size(), 2)
	assert_eq(listed[0].nickname, "모아")
	listed[0].nickname = "mutated"
	listed[0].settings.reduced_motion = true
	assert_eq(service.get_profile(first.profile.profile_id).nickname, "모아")
	assert_false(service.get_profile(first.profile.profile_id).settings.reduced_motion)
	service.free()

func _test_persisted_invalid_nicknames_and_integers_are_rejected() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var service := ProfileService.new(store)
	var created := service.create_profile("모아", "moa_coral", "1234")
	var base_index: Dictionary = store.load("profiles.json").value
	for nickname in ["", "   ", "12345678901234567"]:
		var invalid_nickname_index := base_index.duplicate(true)
		invalid_nickname_index.profiles[0].nickname = nickname
		assert_eq(store.save("profiles.json", invalid_nickname_index), OK)
		var reloaded_nickname := ProfileService.new(store)
		assert_eq(reloaded_nickname.get_profile(created.profile.profile_id), {})
		reloaded_nickname.free()
	for integer_key in ["failed_attempts", "locked_until", "created_at"]:
		for invalid_integer in [1.5]:
			var invalid_integer_index := base_index.duplicate(true)
			invalid_integer_index.profiles[0][integer_key] = invalid_integer
			assert_eq(store.save("profiles.json", invalid_integer_index), OK)
			var reloaded_integer := ProfileService.new(store)
			assert_eq(reloaded_integer.get_profile(created.profile.profile_id), {})
			reloaded_integer.free()
	for integer_key in ["failed_attempts", "locked_until", "created_at"]:
		for invalid_integer in [1.5, INF, -1, 1e100]:
			var invalid_record: Dictionary = base_index.profiles[0].duplicate(true)
			invalid_record[integer_key] = invalid_integer
			assert_eq(ProfileRecord.from_dictionary(invalid_record), {})
	service.free()

func _test_persisted_unknown_fields_are_stripped_and_index_shape_is_validated() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var service := ProfileService.new(store)
	var first := service.create_profile("하늘", "moa_sky", "1234")
	var second := service.create_profile("바다", "moa_mint", "5678")
	var injected_index: Dictionary = store.load("profiles.json").value
	injected_index.profiles[0].pin = "1234"
	injected_index.profiles[0].progress = {"level": 9}
	injected_index.profiles[0].unexpected = true
	assert_eq(store.save("profiles.json", injected_index), OK)
	var reloaded := ProfileService.new(store)
	assert_false(reloaded.read_index_for_test().profiles[0].has("pin"))
	assert_false(reloaded.read_index_for_test().profiles[0].has("progress"))
	assert_false(reloaded.read_index_for_test().profiles[0].has("unexpected"))
	assert_eq(reloaded.update_settings(first.profile.profile_id, {"reduced_motion": true}), OK)
	var saved_index: Dictionary = store.load("profiles.json").value
	assert_false(saved_index.profiles[0].has("pin"))
	assert_false(saved_index.profiles[0].has("progress"))
	assert_false(saved_index.profiles[0].has("unexpected"))
	assert_false(JSON.stringify(saved_index).contains("1234"))
	assert_false(JSON.stringify(saved_index).contains("5678"))
	var wrong_schema := saved_index.duplicate(true)
	wrong_schema.schema_version = 2
	var wrong_selection_type := saved_index.duplicate(true)
	wrong_selection_type.selected_profile_id = 4
	var wrong_profiles_shape := saved_index.duplicate(true)
	wrong_profiles_shape.profiles = {}
	var extra_top_level_key := saved_index.duplicate(true)
	extra_top_level_key.progress = {}
	for malformed_index in [wrong_schema, wrong_selection_type, wrong_profiles_shape, extra_top_level_key]:
		assert_eq(store.save("profiles.json", malformed_index), OK)
		var malformed_reload := ProfileService.new(store)
		assert_eq(malformed_reload.get_profile(second.profile.profile_id), {})
		malformed_reload.free()
	reloaded.free()
	service.free()

func _test_malformed_store_response_does_not_fallback() -> void:
	var store := MalformedStore.new()
	var service := ProfileService.new(store)
	assert_eq(store.load_calls, 1)
	assert_eq(service.create_profile("모아", "moa_coral", "1234").error, "save_failed")
	assert_eq(store.save_calls, 1)
	service.free()

func _test_lock_state_persists_and_is_isolated() -> void:
	var store := AtomicJsonStore.new(BASE_PATH)
	var service := ProfileService.new(store)
	var a := service.create_profile("하늘", "moa_sky", "1234")
	var b := service.create_profile("바다", "moa_mint", "5678")
	for attempt in range(5):
		assert_eq(service.verify_and_select(a.profile.profile_id, "0000", 1000).error, "invalid_pin")
	assert_eq(service.verify_and_select(a.profile.profile_id, "1234", 1001).error, "pin_locked")
	assert_true(service.verify_and_select(b.profile.profile_id, "5678", 1001).ok)
	var reloaded := ProfileService.new(store)
	assert_eq(reloaded.verify_and_select(a.profile.profile_id, "1234", 1001).error, "pin_locked")
	assert_true(reloaded.verify_and_select(a.profile.profile_id, "1234", 1031).ok)
	service.free()
	reloaded.free()

func _test_settings_patch_is_validated() -> void:
	var service := ProfileService.new(AtomicJsonStore.new(BASE_PATH))
	var created := service.create_profile("모아", "moa_coral", "1234")
	assert_eq(service.update_settings(created.profile.profile_id, {"unknown": true}), ERR_INVALID_PARAMETER)
	assert_eq(service.update_settings(created.profile.profile_id, {"reduced_motion": "yes"}), ERR_INVALID_PARAMETER)
	assert_eq(service.update_settings(created.profile.profile_id, {"master_db": 13.0}), ERR_INVALID_PARAMETER)
	assert_eq(service.update_settings(created.profile.profile_id, {"effect_quality": "ultra"}), ERR_INVALID_PARAMETER)
	assert_eq(service.update_settings(created.profile.profile_id, {"voice_enabled": false, "music_db": -12.5}), OK)
	assert_eq(service.get_profile(created.profile.profile_id).settings.music_db, -12.5)
	assert_false(service.get_profile(created.profile.profile_id).settings.voice_enabled)
	service.free()

func _test_save_failures_do_not_mutate_service_state() -> void:
	var service := ProfileService.new(FailingSaveStore.new())
	assert_eq(service.create_profile("모아", "moa_coral", "1234").error, "save_failed")
	assert_eq(service.read_index_for_test().profiles.size(), 0)
	service.free()

func _test_settings_and_selection_save_failures_rollback() -> void:
	var store := ToggleSaveStore.new(BASE_PATH)
	var service := ProfileService.new(store)
	var created := service.create_profile("모아", "moa_coral", "1234")
	store.fail_saves = true
	assert_eq(service.update_settings(created.profile.profile_id, {"reduced_motion": true}), ERR_CANT_CREATE)
	assert_false(service.get_profile(created.profile.profile_id).settings.reduced_motion)
	assert_eq(service.verify_and_select(created.profile.profile_id, "1234", 1000).error, "save_failed")
	assert_eq(service.selected_profile(), {})
	service.free()

func _test_failed_pin_save_failure_rolls_back_security_state() -> void:
	var store := ToggleSaveStore.new(BASE_PATH)
	var service := ProfileService.new(store)
	var created := service.create_profile("모아", "moa_coral", "1234")
	store.fail_saves = true
	assert_eq(service.verify_and_select(created.profile.profile_id, "0000", 1000).error, "save_failed")
	assert_eq(service.read_index_for_test().profiles[0].failed_attempts, 0)
	assert_eq(service.read_index_for_test().profiles[0].locked_until, 0)
	assert_eq(service.verify_and_select(created.profile.profile_id, "0000", -1).error, "invalid_request")
	assert_eq(service.verify_and_select(created.profile.profile_id, "0000", 9007199254740962).error, "invalid_request")
	service.free()

func _cleanup_files(file_names: Array[String]) -> void:
	for file_name in file_names:
		var file_path := "%s/%s" % [BASE_PATH, file_name]
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
