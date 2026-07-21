class_name AppRouter
extends RefCounted

signal route_changed(route: StringName, params: Dictionary)

const AppRouteScript = preload("res://src/app/app_route.gd")

var _host: Control
var _scenes: Dictionary = {}
var _stack: Array[Dictionary] = []
var _current_node: Control

func _init(host: Control = null, route_scenes: Dictionary = {}) -> void:
	_host = host
	set_route_scenes(route_scenes)

func set_route_scenes(route_scenes: Dictionary) -> Dictionary:
	var validated := {}
	for raw_route in route_scenes:
		if not (raw_route is String or raw_route is StringName):
			return {"ok": false, "error": "invalid_route_map"}
		var route := StringName(raw_route)
		var scene: Variant = route_scenes[raw_route]
		if not AppRouteScript.is_known(route) or not scene is PackedScene:
			return {"ok": false, "error": "invalid_route_map"}
		validated[route] = scene
	_scenes = validated
	return {"ok": true}

func navigate(route: StringName, params: Dictionary = {}) -> Dictionary:
	return _transition(route, params, &"push")

func replace(route: StringName, params: Dictionary = {}) -> Dictionary:
	return _transition(route, params, &"replace")

func back() -> bool:
	if _stack.size() <= 1:
		return false
	var target: Dictionary = _stack[_stack.size() - 2].duplicate(true)
	var created := _create_route(target.route, target.params)
	if not created.get("ok", false):
		return false
	_swap_current(created.node)
	_stack.pop_back()
	route_changed.emit(target.route, target.params.duplicate(true))
	return true

func current_route() -> StringName:
	return _stack.back().route if not _stack.is_empty() else &""

func current_params() -> Dictionary:
	return _stack.back().params.duplicate(true) if not _stack.is_empty() else {}

func depth() -> int:
	return _stack.size()

func _transition(route: StringName, params: Dictionary, mode: StringName) -> Dictionary:
	if mode not in [&"push", &"replace"]:
		return {"ok": false, "error": "invalid_navigation"}
	var created := _create_route(route, params)
	if not created.get("ok", false):
		return created
	var record := {"route": route, "params": params.duplicate(true)}
	_swap_current(created.node)
	if mode == &"push" or _stack.is_empty():
		_stack.append(record)
	else:
		_stack[_stack.size() - 1] = record
	route_changed.emit(route, params.duplicate(true))
	return {"ok": true, "route": route, "params": params.duplicate(true)}

func _create_route(route: StringName, params: Dictionary) -> Dictionary:
	if not is_instance_valid(_host):
		return {"ok": false, "error": "invalid_host"}
	if not AppRouteScript.is_known(route) or not _scenes.has(route):
		return {"ok": false, "error": "unknown_route"}
	var instance: Node = _scenes[route].instantiate()
	if instance == null:
		return {"ok": false, "error": "invalid_route_scene"}
	if not instance is Control:
		instance.free()
		return {"ok": false, "error": "invalid_route_scene"}
	var screen: Control = instance
	if screen.has_method("configure"):
		screen.call("configure", params.duplicate(true))
	return {"ok": true, "node": screen}

func _swap_current(next_node: Control) -> void:
	if is_instance_valid(_current_node):
		if _current_node.get_parent() != null:
			_current_node.get_parent().remove_child(_current_node)
		_current_node.queue_free()
	_current_node = next_node
	_host.add_child(_current_node)
	_current_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
