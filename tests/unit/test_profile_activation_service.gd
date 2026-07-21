extends "res://tests/support/test_case.gd"

const ACTIVATION_PATH := "res://src/app/profile_activation_service.gd"
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")

const BASE_PATH := "user://tests/profile_activation"
const DEVICE_ID := "17f0c6b8-4f8d-4d59-9c1a-8af4310d835f"

class FakeJournal extends RefCounted:
	var configure_calls: Array[Dictionary] = []
	var fail_configure := false

	func configure(profile_id: String, device_id: String, path: String) -> Dictionary:
		configure_calls.append({"profile_id": profile_id, "device_id": device_id, "path": path})
		return {"ok": false, "error": "journal_failed"} if fail_configure else {"ok": true, "quarantined_tail": false}

	func replay() -> Dictionary:
		return {"ok": true, "events": [], "quarantined_tail": false}

class FakeProgress extends Node:
	var load_calls: Array[Dictionary] = []
	var fail_load := false
	var profile_id := ""

	func load_profile(next_profile_id: String, journal: Variant) -> Dictionary:
		load_calls.append({"profile_id": next_profile_id, "journal": journal})
		if fail_load:
			return {"ok": false, "error": "progress_failed"}
		profile_id = next_profile_id
		return {"ok": true, "snapshot": {"profile_id": profile_id}}

	func snapshot() -> Dictionary:
		return {"profile_id": profile_id}

class FakeAudio extends RefCounted:
	var applied: Array[Dictionary] = []
	var fail_next := false

	func apply_settings(settings: Dictionary) -> bool:
		if fail_next:
			fail_next = false
			return false
		applied.append(settings.duplicate(true))
		return true

class FakeEffects extends RefCounted:
	var policies: Array[Dictionary] = []
	var fail_next := false

	func set_policy(quality: StringName, reduced_motion: bool) -> bool:
		if fail_next:
			fail_next = false
			return false
		policies.append({"quality": quality, "reduced_motion": reduced_motion})
		return true

class FakeUiPolicy extends RefCounted:
	var values: Array[bool] = []

	func set_reduced_motion(value: bool) -> void:
		values.append(value)

func run(_tree: SceneTree) -> void:
	_cleanup()
	assert_true(ResourceLoader.exists(ACTIVATION_PATH), "profile activation boundary is missing")
	if not ResourceLoader.exists(ACTIVATION_PATH):
		return
	var ActivationScript: Variant = load(ACTIVATION_PATH)
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new(BASE_PATH))
	var first := profile_service.create_profile("하늘", "moa_sky", "1234")
	var second := profile_service.create_profile("바다", "moa_mint", "5678")
	assert_true(first.ok and second.ok)
	assert_eq(profile_service.update_settings(second.profile.profile_id, {
		"effect_quality": "low",
		"reduced_motion": true,
		"voice_enabled": false,
		"music_db": -18.0,
	}), OK)

	var journals: Array[FakeJournal] = []
	var progresses: Array[FakeProgress] = []
	var audio := FakeAudio.new()
	var effects := FakeEffects.new()
	var ui_policy := FakeUiPolicy.new()
	var activation: Variant = ActivationScript.new(
		DEVICE_ID,
		audio,
		effects,
		ui_policy,
		func():
			var journal := FakeJournal.new()
			journals.append(journal)
			return journal,
		func():
			var progress := FakeProgress.new()
			progresses.append(progress)
			return progress,
		func(profile_id: String): return "user://tests/profile_activation/%s/events.jsonl" % profile_id
	)

	var activated_first: Dictionary = activation.activate(profile_service, first.profile.profile_id, "1234", 1000)
	assert_true(activated_first.ok)
	assert_eq(profile_service.selected_profile().profile_id, first.profile.profile_id)
	assert_eq(journals[0].configure_calls[0], {
		"profile_id": first.profile.profile_id,
		"device_id": DEVICE_ID,
		"path": "user://tests/profile_activation/%s/events.jsonl" % first.profile.profile_id,
	})
	assert_eq(progresses[0].load_calls[0].profile_id, first.profile.profile_id)

	var activated_second: Dictionary = activation.activate(profile_service, second.profile.profile_id, "5678", 1001)
	assert_true(activated_second.ok)
	assert_eq(profile_service.selected_profile().profile_id, second.profile.profile_id)
	assert_eq(activated_second.progress_service.snapshot(), {"profile_id": second.profile.profile_id})
	assert_eq(journals[1].configure_calls[0].profile_id, second.profile.profile_id)
	assert_eq(progresses[1].load_calls[0].profile_id, second.profile.profile_id)
	assert_eq(audio.applied.back().music_db, -18.0)
	assert_false(audio.applied.back().voice_enabled)
	assert_eq(effects.policies.back(), {"quality": &"low", "reduced_motion": true})
	assert_true(ui_policy.values.back())

	effects.fail_next = true
	var rejected: Dictionary = activation.activate(profile_service, first.profile.profile_id, "1234", 1002)
	assert_false(rejected.ok)
	assert_eq(rejected.error, "effects_apply_failed")
	assert_eq(profile_service.selected_profile().profile_id, second.profile.profile_id, "failed activation must restore selection")
	assert_eq(audio.applied.back().music_db, -18.0, "failed activation must restore live audio")
	assert_eq(effects.policies.back(), {"quality": &"low", "reduced_motion": true}, "failed activation must restore effects")
	assert_true(ui_policy.values.back(), "failed activation must retain the prior UI policy")

	for result in [activated_first, activated_second]:
		var progress: Variant = result.get("progress_service")
		if progress != null and is_instance_valid(progress):
			progress.free()
	profile_service.free()
	_cleanup()

func _cleanup() -> void:
	for file_name in ["profiles.json", "profiles.json.tmp", "profiles.json.bak"]:
		var path := "%s/%s" % [BASE_PATH, file_name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
