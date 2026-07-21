extends "res://tests/support/test_case.gd"

const CloudCompositionScript = preload("res://src/sync/cloud_sync_composition.gd")
const RemoteUpdaterScript = preload("res://src/content/remote_content_updater.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")

class FakeRepository extends RefCounted:
	func initialize(_manifest_path: String, _cache_root: String) -> Variant:
		return null

func run(_tree: SceneTree) -> void:
	var repository := FakeRepository.new()
	var default_off := CloudCompositionScript.new({
		"http_json_transport": FakeTransportScript.new(),
	}, "device-1")
	assert_null(default_off.create_content_updater(repository, "user://content"))

	var enabled := CloudCompositionScript.new({
		"http_json_transport": FakeTransportScript.new(),
		"remote_content_update_config": {
			"enabled": true,
			"manifest_url": "https://content.mathland.example/active-manifest.json",
			"content_base_url": "https://content.mathland.example/",
		},
	}, "device-1")
	var updater: Variant = enabled.create_content_updater(repository, "user://content")
	assert_not_null(updater)
	if updater != null:
		assert_eq(updater.get_script(), RemoteUpdaterScript)

	for unsafe_config in [
		{"enabled": true, "manifest_url": "http://content.example/active-manifest.json", "content_base_url": "https://content.example/"},
		{"enabled": true, "manifest_url": "https://localhost/active-manifest.json", "content_base_url": "https://localhost/"},
		{"enabled": true, "manifest_url": "https://content.example/active-manifest.json?token=secret", "content_base_url": "https://content.example/"},
		{"enabled": true, "manifest_url": "https://content.example/active-manifest.json", "content_base_url": "https://user:secret@content.example/"},
	]:
		var rejected := CloudCompositionScript.new({
			"http_json_transport": FakeTransportScript.new(),
			"remote_content_update_config": unsafe_config,
		}, "device-1")
		assert_null(rejected.create_content_updater(repository, "user://content"))
