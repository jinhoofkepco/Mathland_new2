class_name SecureCredentialStore
extends RefCounted

const SINGLETON_NAME := "MathLandSecureCredentials"
const REQUIRED_METHODS: Array[StringName] = [
	&"saveRefreshToken",
	&"loadRefreshToken",
	&"clearRefreshToken",
	&"hasRefreshToken",
]

var _plugin: Object

func _init(plugin_override: Object = null, discover_plugin: bool = true) -> void:
	_plugin = plugin_override
	if _plugin == null and discover_plugin and Engine.has_singleton(SINGLETON_NAME):
		_plugin = Engine.get_singleton(SINGLETON_NAME)

func is_available() -> bool:
	if _plugin == null:
		return false
	for method_name in REQUIRED_METHODS:
		if not _plugin.has_method(method_name):
			return false
	return true

func save_refresh_token(token: String) -> bool:
	if token.is_empty() or not is_available():
		return false
	return bool(_plugin.call(&"saveRefreshToken", token))

func load_refresh_token() -> String:
	if not is_available():
		return ""
	var value: Variant = _plugin.call(&"loadRefreshToken")
	return value if value is String else ""

func clear_refresh_token() -> bool:
	if not is_available():
		return false
	return bool(_plugin.call(&"clearRefreshToken"))

func has_refresh_token() -> bool:
	if not is_available():
		return false
	return bool(_plugin.call(&"hasRefreshToken"))
