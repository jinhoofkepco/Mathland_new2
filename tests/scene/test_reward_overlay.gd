extends "res://tests/support/test_case.gd"

const RewardOverlayScene = preload("res://scenes/game/reward_overlay.tscn")

func run(tree: SceneTree) -> void:
	await _test_background_tap_dismisses_once(tree)
	await _test_accept_dismisses_once(tree)
	await _test_button_dismisses_once_and_presets_are_exposed(tree)

func _test_background_tap_dismisses_once(tree: SceneTree) -> void:
	var overlay := await _mount(tree, "reward")
	var dismissals := [0]
	overlay.dismissed.connect(func(): dismissals[0] += 1)
	tree.root.push_input(_mouse_button(Vector2(8, 760), true), true)
	tree.root.push_input(_mouse_button(Vector2(8, 760), false), true)
	await tree.process_frame
	assert_eq(dismissals[0], 1, "a blank overlay tap did not dismiss")
	overlay.dismiss()
	assert_eq(dismissals[0], 1, "dismissed emitted more than once")
	overlay.queue_free()
	await tree.process_frame

func _test_accept_dismisses_once(tree: SceneTree) -> void:
	var overlay := await _mount(tree, "collection")
	var dismissals := [0]
	overlay.dismissed.connect(func(): dismissals[0] += 1)
	assert_true(overlay.has_method("_gui_input"), "RewardOverlay must handle accept input")
	assert_eq(overlay.focus_mode, Control.FOCUS_ALL, "RewardOverlay must be focusable for controller accept")
	if overlay.has_method("_gui_input") and overlay.focus_mode == Control.FOCUS_ALL:
		overlay.grab_focus()
		overlay._gui_input(_accept_key(true))
		overlay._gui_input(_accept_key(false))
	assert_eq(dismissals[0], 1, "keyboard/controller accept did not dismiss exactly once")
	overlay.queue_free()
	await tree.process_frame

func _test_button_dismisses_once_and_presets_are_exposed(tree: SceneTree) -> void:
	for kind in ["reward", "collection", "coupon"]:
		var overlay := await _mount(tree, kind)
		assert_true(overlay.has_method("preset_kind"), "RewardOverlay must expose the resolved preset")
		if overlay.has_method("preset_kind"):
			assert_eq(overlay.preset_kind(), kind)
		var dismissals := [0]
		overlay.dismissed.connect(func(): dismissals[0] += 1)
		var button: Control = overlay.find_child("SkipRewardButton", true, false)
		assert_not_null(button)
		button.accepted.emit()
		button.accepted.emit()
		assert_eq(dismissals[0], 1, "%s preset button dismissed more than once" % kind)
		overlay.queue_free()
		await tree.process_frame

func _mount(tree: SceneTree, kind: String) -> Control:
	var overlay: Control = RewardOverlayScene.instantiate()
	overlay.configure({"kind": kind, "amount": 2})
	tree.root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	return overlay

func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	return event

func _accept_key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = pressed
	return event
