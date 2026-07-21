extends "res://tests/support/test_case.gd"

const AppShellScene = preload("res://scenes/app/app_shell.tscn")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")
const CloudSyncScript = preload("res://src/sync/cloud_sync_service.gd")
const OfflineSyncScript = preload("res://src/sync/offline_sync_service.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")
const FakeCredentialsScript = preload("res://tests/support/fake_secure_credential_store.gd")

const BASE_PATH := "user://tests/cloud_app_shell"
const DEVICE_ID := "6f2ec8c7-7270-44c7-9737-33885f9b9cd4"
const VALID_CONFIG := {
	"supabase_url": "https://mathland.example.supabase.co",
	"publishable_key": "sb_publishable_test",
}

class TestAudio extends Node:
	func apply_settings(_settings: Dictionary) -> bool:
		return true

	func play_music(_music_id: StringName) -> bool:
		return true

class TestLifecycle extends Node:
	func configure_runtime_dependencies(_repository: Variant, _engine: Variant) -> Dictionary:
		return {"ok": true}

	func configure(_profile_id: String, _journal: Variant, _progress: Variant, _router: Variant) -> Dictionary:
		return {"ok": true}

	func restore_if_present() -> Dictionary:
		return {"ok": true, "restored": false}

class FailingRemoteUpdater extends RefCounted:
	var calls := 0

	func check_and_install() -> Dictionary:
		calls += 1
		return {"ok": false, "status": "manifest_network"}

func run(tree: SceneTree) -> void:
	_remove_tree(BASE_PATH)
	await _assert_service_selection(tree, VALID_CONFIG, true, CloudSyncScript)
	await _assert_service_selection(tree, {
		"supabase_url": "http://insecure.example",
		"publishable_key": "sb_publishable_test",
	}, true, OfflineSyncScript)
	await _assert_service_selection(tree, VALID_CONFIG, false, OfflineSyncScript)
	await _assert_remote_update_failure_is_nonblocking(tree)
	_remove_tree(BASE_PATH)

func _assert_remote_update_failure_is_nonblocking(tree: SceneTree) -> void:
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new("%s/remote/index" % BASE_PATH))
	var updater := FailingRemoteUpdater.new()
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": TestAudio.new(),
		"effects_service": null,
		"app_lifecycle": TestLifecycle.new(),
		"remote_content_updater": updater,
		"auto_sync_on_activation": false,
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	await tree.process_frame
	assert_eq(updater.calls, 1, "opt-in remote content updater was never called")
	assert_eq(shell.current_route(), &"profile_select", "background update failure blocked app bootstrap")
	shell.queue_free()
	await tree.process_frame
	profile_service.free()

func _assert_service_selection(
	tree: SceneTree,
	config: Dictionary,
	credentials_available: bool,
	expected_script: GDScript
) -> void:
	var case_id := "%s-%s" % ["valid" if config.supabase_url.begins_with("https://") else "invalid", credentials_available]
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new("%s/%s/index" % [BASE_PATH, case_id]))
	var created: Dictionary = profile_service.create_profile("모아", "moa_mint", "1234")
	assert_true(created.ok)
	var profile_id := String(created.profile.profile_id)
	var credentials := FakeCredentialsScript.new()
	credentials.available = credentials_available
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": TestAudio.new(),
		"effects_service": null,
		"app_lifecycle": TestLifecycle.new(),
		"cloud_public_config": config,
		"secure_credential_store": credentials,
		"http_json_transport": FakeTransportScript.new(),
		"auto_sync_on_activation": false,
		"progress_factory": func(): return ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/%s/progress" % [BASE_PATH, case_id])),
		"journal_path_builder": func(_candidate_profile_id: String): return "%s/%s/events.jsonl" % [BASE_PATH, case_id],
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	var activation: Dictionary = shell.activate_profile(profile_id, "1234", 1000)
	assert_true(activation.ok)
	if activation.get("ok", false):
		var service: Variant = activation.route_params.sync_service
		assert_true(service != null)
		if service != null:
			assert_eq(service.get_script(), expected_script)
		assert_eq(activation.route_params.journal, activation.journal)
		assert_eq(activation.route_params.progress_service, activation.progress_service)
	shell.queue_free()
	await tree.process_frame
	profile_service.free()

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_remove_contents(absolute)
	DirAccess.remove_absolute(absolute)

func _remove_contents(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_contents(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
