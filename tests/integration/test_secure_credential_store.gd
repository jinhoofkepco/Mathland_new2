extends "res://tests/support/test_case.gd"

const SecureCredentialStoreScript = preload("res://src/platform/secure_credential_store.gd")
const FakeSecureCredentialsPluginScript = preload("res://tests/integration/fakes/fake_secure_credentials_plugin.gd")

func run(_tree: SceneTree) -> void:
	_test_round_trip_delegates_to_plugin()
	_test_missing_android_plugin_fails_closed()
	_test_blank_token_and_incomplete_plugin_fail_closed()
	_test_plugin_failures_are_propagated()

func _test_round_trip_delegates_to_plugin() -> void:
	var plugin = FakeSecureCredentialsPluginScript.new()
	var store = SecureCredentialStoreScript.new(plugin)

	assert_true(store.is_available())
	assert_false(store.has_refresh_token())
	assert_true(store.save_refresh_token("refresh-token"))
	assert_eq(store.load_refresh_token(), "refresh-token")
	assert_true(store.has_refresh_token())
	assert_true(store.clear_refresh_token())
	assert_eq(store.load_refresh_token(), "")
	assert_false(store.has_refresh_token())
	assert_eq(plugin.save_calls, 1)
	assert_eq(plugin.clear_calls, 1)

func _test_missing_android_plugin_fails_closed() -> void:
	var store = SecureCredentialStoreScript.new(null, false)

	assert_false(store.is_available())
	assert_false(store.save_refresh_token("refresh-token"))
	assert_eq(store.load_refresh_token(), "")
	assert_false(store.has_refresh_token())
	assert_false(store.clear_refresh_token())

func _test_blank_token_and_incomplete_plugin_fail_closed() -> void:
	var plugin = FakeSecureCredentialsPluginScript.new()
	var store = SecureCredentialStoreScript.new(plugin)

	assert_false(store.save_refresh_token(""))
	assert_eq(plugin.save_calls, 0)
	var incomplete_store = SecureCredentialStoreScript.new(RefCounted.new())
	assert_false(incomplete_store.is_available())
	assert_false(incomplete_store.save_refresh_token("refresh-token"))
	assert_eq(incomplete_store.load_refresh_token(), "")
	assert_false(incomplete_store.has_refresh_token())
	assert_false(incomplete_store.clear_refresh_token())

func _test_plugin_failures_are_propagated() -> void:
	var plugin = FakeSecureCredentialsPluginScript.new()
	var store = SecureCredentialStoreScript.new(plugin)
	plugin.accept_save = false
	assert_false(store.save_refresh_token("refresh-token"))
	assert_false(store.has_refresh_token())
	plugin.accept_save = true
	assert_true(store.save_refresh_token("refresh-token"))
	plugin.accept_clear = false
	assert_false(store.clear_refresh_token())
	assert_eq(store.load_refresh_token(), "refresh-token")
