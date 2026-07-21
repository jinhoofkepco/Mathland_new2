extends "res://tests/support/test_case.gd"

const RewardOverlayScene = preload("res://scenes/game/reward_overlay.tscn")

class RecordingAudioService extends Node:
	var sfx: Array[StringName] = []
	var policies: Array[Dictionary] = []
	var toggles: Array[StringName] = []
	var stopped := 0

	func play_sfx(id: StringName) -> bool:
		sfx.append(id)
		return true

	func play_policy_voice(policy: StringName, context: Dictionary = {}, authorized := false) -> bool:
		policies.append({"policy": policy, "context": context.duplicate(true), "authorized": authorized})
		return authorized

	func dialogue_for_policy(policy: StringName, _context: Dictionary = {}) -> StringName:
		if policy == &"level_up_event":
			return &"moa_level_up"
		return &"moa_reward" if policy == &"reward_event" else &""

	func toggle_voice(dialogue_id: StringName) -> bool:
		toggles.append(dialogue_id)
		return true

	func stop_voice() -> void:
		stopped += 1

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
	for kind in ["reward", "collection", "coupon", "level_up"]:
		var audio := RecordingAudioService.new()
		var overlay := await _mount(tree, kind, audio, true)
		assert_true(overlay.has_method("preset_kind"), "RewardOverlay must expose the resolved preset")
		if overlay.has_method("preset_kind"):
			assert_eq(overlay.preset_kind(), kind)
		var dismissals := [0]
		overlay.dismissed.connect(func(): dismissals[0] += 1)
		var voice_button: Control = overlay.find_child("RewardVoiceButton", true, false)
		assert_not_null(voice_button, "%s preset has no visible replay/stop voice control" % kind)
		if voice_button != null:
			assert_true(voice_button.is_visible_in_tree())
			voice_button.accepted.emit()
			assert_eq(audio.toggles, [&"moa_level_up"] if kind == "level_up" else [&"moa_reward"])
		var button: Control = overlay.find_child("SkipRewardButton", true, false)
		assert_not_null(button)
		button.accepted.emit()
		button.accepted.emit()
		assert_eq(dismissals[0], 1, "%s preset button dismissed more than once" % kind)
		assert_true(&"reward" in audio.sfx, "%s reward presentation did not use reward SFX" % kind)
		var expected_policy := &"level_up_event" if kind == "level_up" else &"reward_event"
		assert_eq(audio.policies, [{"policy": expected_policy, "context": {"kind": kind}, "authorized": true}])
		assert_eq(audio.stopped, 1, "%s dismissal did not stop skippable voice" % kind)
		overlay.queue_free()
		await tree.process_frame
		audio.free()

func _mount(tree: SceneTree, kind: String, audio_service: Variant = null, voice_autoplay_allowed := false) -> Control:
	var overlay: Control = RewardOverlayScene.instantiate()
	overlay.configure({
		"kind": kind,
		"amount": 2,
		"audio_service": audio_service,
		"voice_autoplay_allowed": voice_autoplay_allowed,
	})
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
