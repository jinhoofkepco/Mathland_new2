extends "res://tests/support/test_case.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const AppRouterScript = preload("res://src/app/app_router.gd")
const AppShellScene = preload("res://scenes/app/app_shell.tscn")

class ConfigurableScreen extends Control:
	var configured_params: Dictionary = {}

	func configure(params: Dictionary) -> void:
		configured_params = params.duplicate(true)

func run(tree: SceneTree) -> void:
	_test_push_replace_back_and_unknown_are_contained()
	_test_only_owned_route_node_is_replaced()
	await _test_shell_handles_cancel_without_duplicating_root(tree)
	assert_false(ProjectSettings.get_setting("application/config/quit_on_go_back", true))

func _test_push_replace_back_and_unknown_are_contained() -> void:
	var host := Control.new()
	var scenes := _route_scenes()
	var router := AppRouterScript.new(host, scenes)
	var changes: Array[Dictionary] = []
	router.route_changed.connect(
		func(route: StringName, params: Dictionary):
			changes.append({"route": route, "params": params})
	)
	assert_true(router.navigate(AppRouteScript.PROFILE_SELECT, {"profile": "a"}).ok)
	assert_eq(host.get_child(host.get_child_count() - 1).configured_params, {"profile": "a"})
	assert_true(router.navigate(AppRouteScript.ISLAND, {"island": 1}).ok)
	assert_true(router.navigate(AppRouteScript.FREE_PLAY, {"topic": "addition"}).ok)
	assert_eq(router.current_route(), AppRouteScript.FREE_PLAY)
	assert_eq(router.depth(), 3)
	var exposed := router.current_params()
	exposed["topic"] = "mutated"
	assert_eq(router.current_params(), {"topic": "addition"})
	assert_true(router.back())
	assert_eq(router.current_route(), AppRouteScript.ISLAND)
	assert_eq(router.current_params(), {"island": 1})
	assert_eq(router.depth(), 2)
	assert_true(router.replace(AppRouteScript.RESULT, {"score": 5}).ok)
	assert_eq(router.current_route(), AppRouteScript.RESULT)
	assert_eq(router.depth(), 2, "replace must not grow the stack")
	var before_node: Node = host.get_child(host.get_child_count() - 1)
	var before_changes := changes.size()
	var unknown := router.navigate(&"arbitrary_scene", {"path": "res://escape.tscn"})
	assert_false(unknown.ok)
	assert_eq(unknown.error, "unknown_route")
	assert_eq(router.current_route(), AppRouteScript.RESULT)
	assert_true(host.get_child(host.get_child_count() - 1) == before_node)
	assert_eq(changes.size(), before_changes)
	var invalid_scenes := _route_scenes()
	invalid_scenes[AppRouteScript.SETTINGS] = _packed_non_control()
	assert_true(router.set_route_scenes(invalid_scenes).ok)
	var invalid_scene := router.navigate(AppRouteScript.SETTINGS)
	assert_false(invalid_scene.ok)
	assert_eq(invalid_scene.error, "invalid_route_scene")
	assert_eq(router.current_route(), AppRouteScript.RESULT)
	assert_true(host.get_child(host.get_child_count() - 1) == before_node)
	assert_true(router.back())
	assert_eq(router.current_route(), AppRouteScript.PROFILE_SELECT)
	assert_false(router.back(), "root back must delegate instead of duplicating a screen")
	assert_eq(router.depth(), 1)
	assert_eq(changes.map(func(change): return change.route), [
		AppRouteScript.PROFILE_SELECT,
		AppRouteScript.ISLAND,
		AppRouteScript.FREE_PLAY,
		AppRouteScript.ISLAND,
		AppRouteScript.RESULT,
		AppRouteScript.PROFILE_SELECT,
	])
	host.free()

func _test_only_owned_route_node_is_replaced() -> void:
	var host := Control.new()
	var overlay := ColorRect.new()
	overlay.name = "PersistentOverlay"
	host.add_child(overlay)
	var router := AppRouterScript.new(host, _route_scenes())
	assert_true(router.navigate(AppRouteScript.PROFILE_SELECT).ok)
	var first_route: Node = host.get_child(1)
	assert_true(router.navigate(AppRouteScript.ISLAND).ok)
	assert_true(is_instance_valid(overlay))
	assert_true(overlay.get_parent() == host)
	assert_true(first_route.is_queued_for_deletion())
	assert_eq(host.get_child(host.get_child_count() - 1).name, "Island")
	var configured: Node = host.get_child(host.get_child_count() - 1)
	assert_eq(configured.configured_params, {})
	host.free()

func _test_shell_handles_cancel_without_duplicating_root(tree: SceneTree) -> void:
	var shell: Control = AppShellScene.instantiate()
	tree.root.add_child(shell)
	await tree.process_frame
	var router := AppRouterScript.new(shell.route_host, _route_scenes())
	shell.set_router(router)
	assert_true(router.navigate(AppRouteScript.PROFILE_SELECT).ok)
	assert_true(router.navigate(AppRouteScript.ISLAND).ok)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	shell._unhandled_input(cancel)
	assert_eq(router.current_route(), AppRouteScript.PROFILE_SELECT)
	assert_eq(router.depth(), 1)
	shell._unhandled_input(cancel)
	assert_eq(router.current_route(), AppRouteScript.PROFILE_SELECT)
	assert_eq(router.depth(), 1)
	shell.queue_free()
	await tree.process_frame

func _route_scenes() -> Dictionary:
	return {
		AppRouteScript.PROFILE_SELECT: _packed_screen("ProfileSelect"),
		AppRouteScript.ISLAND: _packed_screen("Island"),
		AppRouteScript.FREE_PLAY: _packed_screen("FreePlay"),
		AppRouteScript.RESULT: _packed_screen("Result"),
	}

func _packed_screen(node_name: String) -> PackedScene:
	var screen := ConfigurableScreen.new()
	screen.name = node_name
	var packed := PackedScene.new()
	assert_eq(packed.pack(screen), OK)
	screen.free()
	return packed

func _packed_non_control() -> PackedScene:
	var node := Node3D.new()
	node.name = "NotAScreen"
	var packed := PackedScene.new()
	assert_eq(packed.pack(node), OK)
	node.free()
	return packed
