class_name AppShell
extends Control

@onready var route_host: Control = %RouteHost
var _router: Variant

func _ready() -> void:
	set_process_unhandled_input(true)

func set_router(router: Variant) -> void:
	assert(router != null and router.has_method("back"), "router must implement back()")
	_router = router

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
