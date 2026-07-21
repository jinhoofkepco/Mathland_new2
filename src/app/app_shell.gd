class_name AppShell
extends Control

const AppRouteScript = preload("res://src/app/app_route.gd")
const AppRouterScript = preload("res://src/app/app_router.gd")
const AudioServiceScript = preload("res://src/presentation/audio/audio_service.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")
const ContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const EFFECTS_SERVICE_PATH := "res://src/presentation/effects/effects_service.gd"
const ROUTE_SCENE_PATHS := {
	AppRouteScript.PROFILE_SELECT: "res://scenes/profile/profile_select.tscn",
	AppRouteScript.ISLAND: "res://scenes/island/exploration_island.tscn",
	AppRouteScript.DAILY_PATH: "res://scenes/island/daily_path.tscn",
	AppRouteScript.FREE_PLAY: "res://scenes/island/free_play.tscn",
	AppRouteScript.INVENTORY: "res://scenes/island/inventory.tscn",
	AppRouteScript.COLLECTION: "res://scenes/island/collection.tscn",
	AppRouteScript.SETTINGS: "res://scenes/island/settings.tscn",
}

@onready var route_host: Control = %RouteHost
var _router: Variant
var _audio_service: Node
var _effects_service: Node
var _progress_service: Node
var _content_repository: RefCounted
var _owns_router := false

func _ready() -> void:
	set_process_unhandled_input(true)
	_bootstrap_default_experience()

func set_router(router: Variant) -> void:
	assert(router != null and router.has_method("back"), "router must implement back()")
	_dispose_owned_router()
	_router = router
	_owns_router = false

func route_scene_paths() -> Dictionary:
	return ROUTE_SCENE_PATHS.duplicate(true)

func handle_back_navigation() -> bool:
	return _router != null and _router.has_method("back") and _router.back()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and handle_back_navigation():
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if not handle_back_navigation() and is_inside_tree():
		get_tree().quit()

func _exit_tree() -> void:
	_dispose_owned_router()
	_content_repository = null

func _bootstrap_default_experience() -> void:
	var profile_service := get_node_or_null("/root/ProfileService")
	if profile_service == null:
		return
	_audio_service = AudioServiceScript.new()
	_audio_service.name = "AudioService"
	add_child(_audio_service)
	_progress_service = ProgressServiceScript.new()
	_progress_service.name = "ProgressService"
	add_child(_progress_service)
	_content_repository = ContentRepositoryScript.new()
	if ResourceLoader.exists(EFFECTS_SERVICE_PATH):
		var effects_script: Variant = load(EFFECTS_SERVICE_PATH)
		if effects_script is GDScript:
			_effects_service = effects_script.new()
			_effects_service.name = "EffectsService"
			add_child(_effects_service)
	var route_scenes := {}
	for route in ROUTE_SCENE_PATHS:
		var packed: Variant = load(ROUTE_SCENE_PATHS[route])
		if packed is PackedScene:
			route_scenes[route] = packed
	_router = AppRouterScript.new(route_host, route_scenes)
	_owns_router = true
	var selected: Dictionary = profile_service.selected_profile()
	var params := {
		"router": weakref(_router),
		"profile_service": profile_service,
		"progress_service": _progress_service,
		"content_repository": _content_repository,
		"audio_service": _audio_service,
		"effects_service": _effects_service,
		"profile_id": selected.get("profile_id", ""),
		"online": false,
		"sync_queue_count": 0,
	}
	if selected.is_empty():
		_router.navigate(AppRouteScript.PROFILE_SELECT, params)
	else:
		_audio_service.apply_settings(selected.settings)
		if _effects_service != null:
			_effects_service.set_policy(StringName(selected.settings.effect_quality), bool(selected.settings.reduced_motion))
		_router.navigate(AppRouteScript.ISLAND, params)

func _dispose_owned_router() -> void:
	if _owns_router and _router != null and _router.has_method("dispose"):
		_router.dispose()
	if _owns_router:
		_router = null
	_owns_router = false
