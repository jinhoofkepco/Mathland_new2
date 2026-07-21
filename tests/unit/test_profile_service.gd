extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/profiles"
const AtomicJsonStore = preload("res://src/persistence/atomic_json_store.gd")
const ProfileService = preload("res://src/profiles/profile_service.gd")

class FailingSaveStore extends AtomicJsonStore:
	func _init() -> void:
		super(BASE_PATH)

	func save(_path: String, _value: Variant) -> Error:
		return ERR_CANT_CREATE

func run(_tree: SceneTree) -> void:
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_profiles_are_isolated_and_pin_is_not_plaintext()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_invalid_profile_inputs_are_rejected()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_lock_state_persists_and_is_isolated()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_settings_patch_is_validated()
	_cleanup_files(["profiles.json", "profiles.json.tmp", "profiles.json.bak"])
	_test_save_failures_do_not_mutate_service_state()
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

func _cleanup_files(file_names: Array[String]) -> void:
	for file_name in file_names:
		var file_path := "%s/%s" % [BASE_PATH, file_name]
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
