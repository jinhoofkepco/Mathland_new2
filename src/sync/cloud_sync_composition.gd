class_name CloudSyncComposition
extends RefCounted

const CloudSyncServiceScript = preload("res://src/sync/cloud_sync_service.gd")
const HttpJsonTransportScript = preload("res://src/sync/http_json_transport.gd")
const SupabaseDeviceAuthScript = preload("res://src/sync/supabase_device_auth.gd")
const SyncRetryPolicyScript = preload("res://src/sync/sync_retry_policy.gd")
const SyncCursorStoreScript = preload("res://src/sync/sync_cursor_store.gd")
const SecureCredentialStoreScript = preload("res://src/platform/secure_credential_store.gd")
const RemoteContentUpdaterScript = preload("res://src/content/remote_content_updater.gd")
const CONFIG_PATH := "res://resources/config/cloud_public.json"
const CONTENT_CONFIG_PATH := "res://resources/config/content_update.json"

var _overrides: Dictionary
var _device_id := ""
var _config: Dictionary = {}
var _content_update_config: Dictionary = {}
var _credential_store: Variant
var _transport: Variant

func _init(overrides: Dictionary, device_id: String) -> void:
	_overrides = overrides.duplicate(false)
	_device_id = device_id
	_config = _load_public_config()
	_content_update_config = _load_content_update_config()
	_credential_store = (
		_overrides.secure_credential_store
		if _overrides.has("secure_credential_store")
		else SecureCredentialStoreScript.new()
	)
	_transport = (
		_overrides.http_json_transport
		if _overrides.has("http_json_transport")
		else HttpJsonTransportScript.new()
	)

func attach_transport(host: Node) -> void:
	if _transport is Node and _transport.get_parent() == null:
		_transport.name = "HttpJsonTransport"
		host.add_child(_transport)

func create_service(journal: Variant, progress_service: Variant, profile_id: String) -> Variant:
	if not is_available():
		return null
	var auth := SupabaseDeviceAuthScript.new(
		_transport, _credential_store, _config, _device_id
	)
	var cursor_store: Variant
	var cursor_factory: Callable = _overrides.get("sync_cursor_store_factory", Callable())
	if cursor_factory.is_valid():
		cursor_store = cursor_factory.call(profile_id, _device_id)
	else:
		cursor_store = SyncCursorStoreScript.new(profile_id, _device_id)
	var retry_policy: Variant = (
		_overrides.sync_retry_policy
		if _overrides.has("sync_retry_policy")
		else SyncRetryPolicyScript.new()
	)
	return CloudSyncServiceScript.new(
		journal,
		progress_service,
		auth,
		_transport,
		cursor_store,
		retry_policy,
		_config
	)

func create_content_updater(repository: Variant, cache_root: String) -> Variant:
	if (
		_content_update_config.is_empty()
		or not bool(_content_update_config.get("enabled", false))
		or _transport == null
		or not _transport.has_method("request_json")
		or repository == null
		or not repository.has_method("initialize")
	):
		return null
	return RemoteContentUpdaterScript.new(
		_transport,
		repository,
		String(_content_update_config.manifest_url),
		String(_content_update_config.content_base_url),
		cache_root,
	)

func is_available() -> bool:
	return (
		not _config.is_empty()
		and _credential_store != null
		and _credential_store.has_method("is_available")
		and _credential_store.is_available()
		and _transport != null
		and _transport.has_method("request_json")
	)

func _load_public_config() -> Dictionary:
	var value: Variant
	if _overrides.has("cloud_public_config"):
		value = _overrides.cloud_public_config
	else:
		if not FileAccess.file_exists(CONFIG_PATH):
			return {}
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file == null or file.get_length() > 4096:
			if file != null:
				file.close()
			return {}
		var source := file.get_as_text()
		file.close()
		value = JSON.parse_string(source)
	if not SupabaseDeviceAuthScript.is_valid_public_config(value):
		return {}
	return (value as Dictionary).duplicate(true)

func _load_content_update_config() -> Dictionary:
	var value: Variant
	if _overrides.has("remote_content_update_config"):
		value = _overrides.remote_content_update_config
	else:
		if not FileAccess.file_exists(CONTENT_CONFIG_PATH):
			return {}
		var file := FileAccess.open(CONTENT_CONFIG_PATH, FileAccess.READ)
		if file == null or file.get_length() > 4096:
			if file != null:
				file.close()
			return {}
		var source := file.get_as_text()
		file.close()
		value = JSON.parse_string(source)
	if not RemoteContentUpdaterScript.is_valid_public_config(value):
		return {}
	return (value as Dictionary).duplicate(true)
