class_name ChildScreen
extends Control

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")

var _params: Dictionary = {}
var _router: Variant
var _profile_service: Variant
var _progress_service: Variant
var _content_repository: Variant
var _audio_service: Variant
var _effects_service: Variant
var _profile_id := ""

func configure(params: Dictionary) -> void:
	_params = params.duplicate(false)
	var router_value: Variant = params.get("router")
	_router = router_value.get_ref() if router_value is WeakRef else router_value
	_profile_service = params.get("profile_service")
	_progress_service = params.get("progress_service")
	_content_repository = params.get("content_repository")
	_audio_service = params.get("audio_service")
	_effects_service = params.get("effects_service")
	_profile_id = String(params.get("profile_id", ""))

func _route(route: StringName, extras: Dictionary = {}) -> Dictionary:
	if _router == null or not _router.has_method("navigate"):
		return {"ok": false, "error": "router_unavailable"}
	var next_params := _params.duplicate(false)
	for key in extras:
		next_params[key] = extras[key]
	return _router.navigate(route, next_params)

func _back() -> bool:
	return _router != null and _router.has_method("back") and _router.back()

func _snapshot() -> Dictionary:
	if _progress_service != null and _progress_service.has_method("snapshot"):
		var value: Variant = _progress_service.snapshot()
		if value is Dictionary:
			return value.duplicate(true)
	return {}

func _profile() -> Dictionary:
	if _profile_service != null and _profile_service.has_method("get_profile") and not _profile_id.is_empty():
		var value: Variant = _profile_service.get_profile(_profile_id)
		if value is Dictionary:
			return value.duplicate(true)
	return {}

func _today() -> String:
	var injected := String(_params.get("date", ""))
	return injected if not injected.is_empty() else Time.get_date_string_from_system()

func _connect_tactile(button: Control, callback: Callable) -> void:
	MathlandUiScript.connect_tactile(button, callback, _audio_service)

func _play_effect(effect_name: StringName, at: Vector2 = Vector2.ZERO) -> void:
	if _effects_service != null and _effects_service.has_method("play"):
		_effects_service.play(effect_name, at)
