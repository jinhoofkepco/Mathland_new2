extends "res://tests/support/test_case.gd"

const TactileButtonScene = preload("res://scenes/shared/tactile_button.tscn")

func run(tree: SceneTree) -> void:
	await _test_pointer_down_release_and_cancel(tree)
	await _test_reduced_motion_keeps_non_motion_feedback(tree)
	await _test_keyboard_acceptance(tree)

func _test_pointer_down_release_and_cancel(tree: SceneTree) -> void:
	var button: Control = TactileButtonScene.instantiate()
	button.position = Vector2(20, 20)
	button.size = Vector2(240, 64)
	tree.root.add_child(button)
	await tree.process_frame
	button.configure_accessibility("다음", "arrow_right")
	assert_eq(button.size, Vector2(240, 64))
	assert_true(button._contains(Vector2(20, 20)))
	var counts := {"presses": 0, "accepted": 0, "cancelled": 0}
	var sfx: Array[StringName] = []
	button.press_started.connect(func(): counts.presses += 1)
	button.accepted.connect(func(): counts.accepted += 1)
	button.cancelled.connect(func(): counts.cancelled += 1)
	button.sfx_requested.connect(func(id: StringName): sfx.append(id))
	var normal_scale: Vector2 = button.get_node("Visual").scale
	var normal_shadow_y: float = button.get_node("Shadow").position.y
	button._gui_input(_mouse_button(Vector2(20, 20), true))
	assert_eq(counts.presses, 1, "press_started must fire in the pointer-down frame")
	assert_eq(sfx, [&"button_down"])
	assert_true(button.get_node("Visual").scale.x < normal_scale.x)
	assert_true(button.get_node("Shadow").position.y < normal_shadow_y)
	button._gui_input(_mouse_button(Vector2(20, 20), false))
	assert_eq(counts.accepted, 1)
	assert_eq(counts.cancelled, 0)
	await tree.create_timer(0.25).timeout
	assert_eq(button.get_node("Visual").scale, Vector2.ONE)

	button._gui_input(_mouse_button(Vector2(20, 20), true))
	button._gui_input(_mouse_motion(Vector2(300, 80)))
	button._gui_input(_mouse_button(Vector2(300, 80), false))
	assert_eq(counts.presses, 2)
	assert_eq(counts.accepted, 1)
	assert_eq(counts.cancelled, 1)
	button._gui_input(_touch(Vector2(20, 20), true, 5))
	button._gui_input(_touch(Vector2(20, 20), false, 6))
	assert_eq(counts.accepted, 1, "another finger cannot accept the active press")
	button._gui_input(_drag(Vector2(300, 80), 5))
	button._gui_input(_touch(Vector2(300, 80), false, 5))
	assert_eq(counts.presses, 3)
	assert_eq(counts.cancelled, 2)
	assert_true(button.custom_minimum_size.x >= 48.0)
	assert_true(button.custom_minimum_size.y >= 48.0)
	assert_eq(button.get_node("Visual/Content/TextLabel").text, "다음")
	assert_false(button.accessibility_name.is_empty())
	assert_false(button.tooltip_text.is_empty())
	button.queue_free()
	await tree.process_frame

func _test_reduced_motion_keeps_non_motion_feedback(tree: SceneTree) -> void:
	var button: Control = TactileButtonScene.instantiate()
	button.size = Vector2(240, 64)
	button.reduced_motion = true
	tree.root.add_child(button)
	await tree.process_frame
	var original_shadow: Color = button.get_node("Shadow").modulate
	button._gui_input(_mouse_button(Vector2(10, 10), true))
	assert_eq(button.get_node("Visual").scale, Vector2.ONE)
	assert_eq(button.get_node("Visual").position, Vector2.ZERO)
	assert_ne(button.get_node("Shadow").modulate, original_shadow)
	button._gui_input(_mouse_button(Vector2(10, 10), false))
	button.queue_free()
	await tree.process_frame

func _test_keyboard_acceptance(tree: SceneTree) -> void:
	var button: Control = TactileButtonScene.instantiate()
	button.size = Vector2(240, 64)
	tree.root.add_child(button)
	await tree.process_frame
	button.grab_focus()
	assert_true(button.get_node("FocusRing").visible)
	var counts := {"accepted": 0}
	button.accepted.connect(func(): counts.accepted += 1)
	button._gui_input(_key_event(true))
	button._gui_input(_key_event(false))
	assert_eq(counts.accepted, 1)
	button.queue_free()
	await tree.process_frame

func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event

func _mouse_motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event

func _key_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = pressed
	return event

func _touch(position: Vector2, pressed: bool, index: int) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = index
	return event

func _drag(position: Vector2, index: int) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	return event
