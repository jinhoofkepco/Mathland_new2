class_name AppShell
extends Control

signal diagnostic(code: String)

const AppRouteScript = preload("res://src/app/app_route.gd")
const AppRouterScript = preload("res://src/app/app_router.gd")
const AudioServiceScript = preload("res://src/presentation/audio/audio_service.gd")
const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const DeviceIdentityScript = preload("res://src/persistence/device_identity.gd")
const ProfileActivationServiceScript = preload("res://src/app/profile_activation_service.gd")
const AppLifecycleScript = preload("res://src/app/app_lifecycle.gd")
const OfflineSyncServiceScript = preload("res://src/sync/offline_sync_service.gd")
const UiPolicyScript = preload("res://src/ui/shared/ui_policy.gd")
const EFFECTS_SERVICE_PATH := "res://src/presentation/effects/effects_service.gd"
const ROUTE_SCENE_PATHS := {
	AppRouteScript.PROFILE_SELECT: "res://scenes/profile/profile_select.tscn",
	AppRouteScript.ISLAND: "res://scenes/island/exploration_island.tscn",
	AppRouteScript.DAILY_PATH: "res://scenes/island/daily_path.tscn",
	AppRouteScript.FREE_PLAY: "res://scenes/island/free_play.tscn",
	AppRouteScript.ACTIVITY_RUN: "res://scenes/game/activity_run.tscn",
	AppRouteScript.RESULT: "res://scenes/game/run_result.tscn",
	AppRouteScript.INVENTORY: "res://scenes/island/inventory.tscn",
	AppRouteScript.COLLECTION: "res://scenes/island/collection.tscn",
	AppRouteScript.SETTINGS: "res://scenes/island/settings.tscn",
}

@onready var route_host: Control = %RouteHost
var _router: Variant
var _profile_service: Variant
var _audio_service: Variant
var _effects_service: Variant
var _progress_service: Variant
var _event_journal: Variant
var _content_repository: Variant
var _question_engine: Variant
var _ui_policy: Variant
var _profile_activation: Variant
var _app_lifecycle: Variant
var _sync_service: Variant
var _dependency_overrides: Dictionary = {}
var _owns_router := false

func _ready() -> void:
	set_process_unhandled_input(true)
	_bootstrap_default_experience()

func set_router(router: Variant) -> void:
	assert(router != null and router.has_method("back"), "router must implement back()")
	_dispose_owned_router()
	_router = router
	_owns_router = false
	_bind_route_audio()

func configure_dependencies(dependencies: Dictionary) -> bool:
	if is_inside_tree():
		return false
	_dependency_overrides = dependencies.duplicate(false)
	return true

func route_scene_paths() -> Dictionary:
	return ROUTE_SCENE_PATHS.duplicate(true)

func current_route() -> StringName:
	return _router.current_route() if _router != null and _router.has_method("current_route") else &""

func activate_profile(profile_id: String, pin: String, now_unix: int) -> Dictionary:
	if _profile_activation == null:
		return {"ok": false, "error": "activation_unavailable"}
	var activated: Variant = _profile_activation.activate(_profile_service, profile_id, pin, now_unix)
	if not activated is Dictionary or not activated.get("ok", false):
		return activated.duplicate(true) if activated is Dictionary else {"ok": false, "error": "invalid_activation_result"}
	var next_progress: Variant = activated.get("progress_service")
	if not next_progress is Node:
		if next_progress is Object and is_instance_valid(next_progress):
			next_progress.free()
		return {"ok": false, "error": "invalid_progress_service"}
	_replace_progress_service(next_progress)
	_event_journal = activated.get("journal")
	_sync_service = OfflineSyncServiceScript.new(_event_journal)
	if _app_lifecycle != null:
		var lifecycle_configured: Variant = _app_lifecycle.configure(
			profile_id, _event_journal, _progress_service, _router
		)
		if not lifecycle_configured is Dictionary or not lifecycle_configured.get("ok", false):
			return {"ok": false, "error": "lifecycle_config_failed"}
	var result: Dictionary = activated.duplicate(false)
	result["route_params"] = _base_route_params(profile_id)
	if _app_lifecycle != null:
		var recovery: Variant = _app_lifecycle.restore_if_present()
		if recovery is Dictionary and recovery.get("ok", false) and recovery.get("restored", false):
			result["resume_route"] = AppRouteScript.ACTIVITY_RUN
			result.route_params["restored_run"] = true
			result.route_params["run_session"] = recovery.run_session
			result.route_params["activity_id"] = recovery.activity.activity_id
			result.route_params["content_version"] = recovery.activity.content_version
			result.route_params["seed"] = int(recovery.current_question.seed)
			result.route_params["recovery_source"] = recovery.source
		elif recovery is Dictionary and not recovery.get("ok", false):
			result["recovery_error"] = String(recovery.get("error", "restore_failed"))
	return result

func handle_back_navigation() -> bool:
	if current_route() == AppRouteScript.ACTIVITY_RUN and _app_lifecycle != null:
		if not _app_lifecycle.has_method("flush_and_checkpoint"):
			return true
		var checkpointed: Variant = _app_lifecycle.flush_and_checkpoint()
		if not checkpointed is Dictionary or not checkpointed.get("ok", false):
			return true
		if _app_lifecycle.has_method("release_active_run"):
			var released: Variant = _app_lifecycle.release_active_run()
			if not released is Dictionary or not released.get("ok", false):
				return true
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
	_event_journal = null
	_sync_service = null
	_app_lifecycle = null
	_profile_activation = null
	_content_repository = null
	_question_engine = null

func _bootstrap_default_experience() -> void:
	_profile_service = _dependency_overrides.get("profile_service", get_node_or_null("/root/ProfileService"))
	if _profile_service == null:
		return
	_audio_service = _dependency_overrides.audio_service if _dependency_overrides.has("audio_service") else AudioServiceScript.new()
	_add_service_child(_audio_service, "AudioService")
	_configure_content_runtime()
	_ui_policy = _dependency_overrides.ui_policy if _dependency_overrides.has("ui_policy") else UiPolicyScript.new()
	if _dependency_overrides.has("effects_service"):
		_effects_service = _dependency_overrides.effects_service
	elif ResourceLoader.exists(EFFECTS_SERVICE_PATH):
		var effects_script: Variant = load(EFFECTS_SERVICE_PATH)
		if effects_script is GDScript:
			_effects_service = effects_script.new()
	_add_service_child(_effects_service, "EffectsService")
	var device_id := String(_dependency_overrides.get("device_id", ""))
	if device_id.is_empty():
		device_id = DeviceIdentityScript.new(AtomicJsonStoreScript.new("user://.")).load_or_create()
	var journal_factory: Callable = _dependency_overrides.get("journal_factory", Callable())
	var progress_factory: Callable = _dependency_overrides.get("progress_factory", Callable())
	var journal_path_builder: Callable = _dependency_overrides.get("journal_path_builder", Callable())
	_profile_activation = ProfileActivationServiceScript.new(
		device_id,
		_audio_service,
		_effects_service,
		_ui_policy,
		journal_factory,
		progress_factory,
		journal_path_builder
	)
	if _dependency_overrides.has("app_lifecycle"):
		_app_lifecycle = _dependency_overrides.app_lifecycle
	else:
		_app_lifecycle = get_node_or_null("/root/LifecycleService")
		if _app_lifecycle == null:
			_app_lifecycle = AppLifecycleScript.new()
		if not _inject_default_lifecycle_runtime():
			diagnostic.emit("content_runtime_injection_failed")
	_add_service_child(_app_lifecycle, "AppLifecycle")
	var route_scenes := {}
	for route in ROUTE_SCENE_PATHS:
		var packed: Variant = load(ROUTE_SCENE_PATHS[route])
		if packed is PackedScene:
			route_scenes[route] = packed
	_router = AppRouterScript.new(route_host, route_scenes)
	_owns_router = true
	_bind_route_audio()
	_router.navigate(AppRouteScript.PROFILE_SELECT, _base_route_params())

func _bind_route_audio() -> void:
	if _router == null or not _router.has_signal("route_changed"):
		return
	var callback := Callable(self, "_on_route_audio_changed")
	if not _router.route_changed.is_connected(callback):
		_router.route_changed.connect(callback)

func _on_route_audio_changed(route: StringName, _params_for_route: Dictionary) -> void:
	if _audio_service == null or not _audio_service.has_method("play_music"):
		return
	var music_id := &"concentration_loop" if route == AppRouteScript.ACTIVITY_RUN else &"exploration_loop"
	_audio_service.play_music(music_id)

func _base_route_params(profile_id: String = "") -> Dictionary:
	var sync_status := {"state": "offline", "pending_count": 0, "last_success_at": null}
	if _sync_service != null and _sync_service.has_method("status"):
		var reported: Variant = _sync_service.status()
		if reported is Dictionary:
			sync_status = reported.duplicate(true)
	var params := {
		"router": weakref(_router),
		"profile_service": _profile_service,
		"profile_activator": weakref(self),
		"progress_service": _progress_service,
		"journal": _event_journal,
		"content_repository": _content_repository,
		"question_engine": _question_engine,
		"audio_service": _audio_service,
		"effects_service": _effects_service,
		"ui_policy": _ui_policy,
		"app_lifecycle": _app_lifecycle,
		"sync_service": _sync_service,
		"profile_id": profile_id,
		"online": sync_status.get("state") == "online",
		"sync_queue_count": maxi(int(sync_status.get("pending_count", 0)), 0),
	}
	if _dependency_overrides.has("response_clock"):
		params["response_clock"] = _dependency_overrides.response_clock
	return params

func _configure_content_runtime() -> void:
	_question_engine = (
		_dependency_overrides.question_engine
		if _dependency_overrides.has("question_engine")
		else QuestionEngineScript.new()
	)
	if _dependency_overrides.has("content_repository"):
		_content_repository = _dependency_overrides.content_repository
		return
	_content_repository = ContentRepositoryScript.new()
	var manifest_path := String(_dependency_overrides.get(
		"content_manifest_path", "res://content/active-manifest.json"
	))
	var cache_root := String(_dependency_overrides.get("content_cache_root", "user://content"))
	var initialized: Variant = _content_repository.initialize(manifest_path, cache_root)
	if not initialized is Object or not bool(initialized.get("ok")):
		diagnostic.emit("content_initialization_failed")

func _inject_default_lifecycle_runtime() -> bool:
	if (
		_app_lifecycle == null
		or not _app_lifecycle.has_method("configure_runtime_dependencies")
	):
		return false
	var configured: Variant = _app_lifecycle.configure_runtime_dependencies(
		_content_repository,
		_question_engine
	)
	return configured is Dictionary and configured.get("ok", false)

func _replace_progress_service(next_progress: Node) -> void:
	var previous: Variant = _progress_service
	if previous is Node and is_instance_valid(previous) and previous != next_progress:
		if previous.get_parent() != null:
			previous.get_parent().remove_child(previous)
		previous.queue_free()
	_progress_service = next_progress
	if next_progress.get_parent() == null:
		next_progress.name = "ProgressService"
		add_child(next_progress)

func _add_service_child(service: Variant, node_name: String) -> void:
	if service is Node and service.get_parent() == null:
		service.name = node_name
		add_child(service)

func _dispose_owned_router() -> void:
	if _owns_router and _router != null and _router.has_method("dispose"):
		_router.dispose()
	if _owns_router:
		_router = null
	_owns_router = false
