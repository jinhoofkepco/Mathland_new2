extends "res://tests/support/test_case.gd"

const VIEWPORT_SIZES := [Vector2i(360, 800), Vector2i(1080, 2400), Vector2i(800, 1280)]
const ROUTE_SCENES := [
	"res://scenes/profile/profile_select.tscn",
	"res://scenes/island/exploration_island.tscn",
	"res://scenes/island/daily_path.tscn",
	"res://scenes/island/free_play.tscn",
	"res://scenes/game/activity_run.tscn",
	"res://scenes/game/run_result.tscn",
	"res://scenes/island/inventory.tscn",
	"res://scenes/island/collection.tscn",
	"res://scenes/island/settings.tscn",
]
const ROUTE_SOURCE_ROOTS := ["res://src/app", "res://src/ui", "res://src/game"]
const DEFAULT_SETTINGS := {
	"adaptive_difficulty": false,
	"timing_aids": true,
	"timers_enabled": true,
	"reduced_motion": true,
	"effect_quality": "high",
	"master_db": 0.0,
	"music_db": -6.0,
	"sfx_db": 0.0,
	"voice_db": 0.0,
	"voice_enabled": true,
}
const RecordingJournalScript = preload("res://tests/support/recording_journal.gd")
const InMemoryProgressServiceScript = preload("res://tests/support/in_memory_progress_service.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const ContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const QuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")
const UiPolicyScript = preload("res://src/ui/shared/ui_policy.gd")
const OfflineSyncServiceScript = preload("res://src/sync/offline_sync_service.gd")
const EffectsServiceScript = preload("res://src/presentation/effects/effects_service.gd")
const TactileButtonScene = preload("res://scenes/shared/tactile_button.tscn")

class FakeRouter extends RefCounted:
	func navigate(_route: StringName, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func replace(_route: StringName, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func reset(_route: StringName, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func back() -> bool:
		return true

class FakeProfileService extends RefCounted:
	func list_profiles() -> Array[Dictionary]:
		return [_profile()]

	func get_profile(profile_id: Variant) -> Dictionary:
		return _profile() if profile_id == "access-profile" else {}

	func update_settings(profile_id: String, _patch: Dictionary) -> Error:
		return OK if profile_id == "access-profile" else ERR_INVALID_PARAMETER

	func _profile() -> Dictionary:
		return {
			"profile_id": "access-profile",
			"nickname": "모아",
			"avatar_id": "moa_mint",
			"settings": DEFAULT_SETTINGS.duplicate(true),
			"created_at": "2026-07-22T00:00:00Z",
		}

class FakeAudioService extends RefCounted:
	func apply_settings(_settings: Dictionary) -> bool:
		return true

	func play_sfx(_id: StringName) -> bool:
		return false

	func play_voice(_id: StringName) -> bool:
		return false

	func stop_voice() -> void:
		pass

class FakeEffectsService extends RefCounted:
	func play(_effect_name: StringName, _at: Vector2) -> bool:
		return true

	func set_policy(_quality: StringName, _reduced_motion: bool) -> bool:
		return true

func run(tree: SceneTree) -> void:
	await _test_every_route_at_supported_viewports(tree)
	await _test_reduced_motion_effect_and_timer_policy(tree)
	await _test_one_hundred_press_feedback_budget(tree)
	_test_route_sources_are_network_free()
	_test_game_scenes_do_not_own_persistence()

func _test_every_route_at_supported_viewports(tree: SceneTree) -> void:
	for viewport_size in VIEWPORT_SIZES:
		for scene_path in ROUTE_SCENES:
			var packed: Variant = load(scene_path)
			assert_true(packed is PackedScene, "missing route scene: %s" % scene_path)
			if not packed is PackedScene:
				continue
			var viewport := SubViewport.new()
			viewport.size = viewport_size
			tree.root.add_child(viewport)
			var screen: Control = packed.instantiate()
			screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var params := _route_params(scene_path)
			if screen.has_method("configure"):
				screen.configure(params)
			viewport.add_child(screen)
			await tree.process_frame
			await tree.process_frame
			assert_eq(screen.size, Vector2(viewport_size), "%s did not fill %s" % [scene_path, viewport_size])
			assert_false(_contains_network_node(screen), "%s created a network node while loading offline" % scene_path)
			var interactives: Array[Control] = []
			_collect_interactives(screen, interactives)
			assert_true(not interactives.is_empty(), "%s exposes no child action" % scene_path)
			for control in interactives:
				if not is_instance_valid(control) or not control.is_visible_in_tree():
					continue
				var scroll := _ancestor_scroll(control)
				if scroll != null:
					scroll.ensure_control_visible(control)
					await tree.process_frame
					await tree.process_frame
				assert_true(control.size.x >= 48.0 and control.size.y >= 48.0, "%s/%s is below 48x48: %s" % [scene_path, control.name, control.size])
				assert_true(_inside_viewport(control, viewport_size), "%s/%s clips at %s" % [scene_path, control.name, viewport_size])
				assert_false(_visible_action_label(control).strip_edges().is_empty(), "%s/%s has no visible label" % [scene_path, control.name])
			viewport.queue_free()
			await tree.process_frame

func _test_reduced_motion_effect_and_timer_policy(tree: SceneTree) -> void:
	var policy := UiPolicyScript.new()
	policy.set_reduced_motion(true)
	var params := _route_params("res://scenes/game/activity_run.tscn", policy)
	var screen: Control = load("res://scenes/game/activity_run.tscn").instantiate()
	screen.configure(params)
	tree.root.add_child(screen)
	await tree.process_frame
	var tactile_controls: Array[Control] = []
	_collect_tactile(screen, tactile_controls)
	assert_true(tactile_controls.size() >= 8)
	for control in tactile_controls:
		assert_true(control.reduced_motion, "%s ignored the profile reduced-motion policy" % control.name)
	var state: Dictionary = screen.current_state()
	assert_false(state.timer_enabled)
	assert_eq(state.timer_started_at_ms, 0)
	assert_eq(state.timer_remaining_ms, 0)
	screen.skip_introduction()
	assert_true(screen.submit_answer(screen.current_question().correct_answer, 100, 0).ok)
	var reward_button: Control = screen.find_child("SkipRewardButton", true, false)
	assert_not_null(reward_button)
	if reward_button != null:
		assert_true(reward_button.reduced_motion, "future reward controls ignored reduced motion")
	var effects := EffectsServiceScript.new()
	tree.root.add_child(effects)
	await tree.process_frame
	assert_true(effects.set_policy(&"high", true))
	assert_true(effects.play(&"boss", Vector2.ZERO))
	assert_eq(effects.latest_burst().configured_shake_amplitude, 0.0)
	assert_eq(effects.latest_burst().configured_translation_amplitude, 0.0)
	effects.latest_burst().finish_now()
	screen.queue_free()
	effects.queue_free()
	await tree.process_frame

func _test_one_hundred_press_feedback_budget(tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var button: Control = TactileButtonScene.instantiate()
	button.position = Vector2(40, 40)
	button.size = Vector2(240, 64)
	button.custom_minimum_size = button.size
	button.haptics_enabled = false
	viewport.add_child(button)
	await tree.process_frame
	var counts := {"accepted": 0}
	button.accepted.connect(func(): counts.accepted += 1)
	var slowest_usec := 0
	for _index in 100:
		var started := Time.get_ticks_usec()
		button.call("_gui_input", _mouse_button(Vector2(120, 32), true))
		button.call("_gui_input", _mouse_button(Vector2(120, 32), false))
		slowest_usec = maxi(slowest_usec, int(Time.get_ticks_usec() - started))
	assert_eq(counts.accepted, 100)
	assert_true(slowest_usec < 100_000, "synchronous press feedback exceeded 100ms: %dus" % slowest_usec)
	viewport.queue_free()
	await tree.process_frame

func _test_route_sources_are_network_free() -> void:
	var sources: Array[String] = []
	for root in ROUTE_SOURCE_ROOTS:
		_collect_gdscript_sources(root, sources)
	for path in sources:
		var source := FileAccess.get_file_as_string(path).to_lower()
		for forbidden in ["httprequest", "httpclient", "websocket", "supabase", "http://", "https://"]:
			assert_false(forbidden in source, "%s contains route-time network dependency %s" % [path, forbidden])

func _test_game_scenes_do_not_own_persistence() -> void:
	var sources: Array[String] = []
	for root in ["res://src/game", "res://src/ui"]:
		_collect_gdscript_sources(root, sources)
	for path in sources:
		var source := FileAccess.get_file_as_string(path)
		for forbidden in ["FileAccess", "DirAccess", "JSON.parse", "JSON.stringify", "HTTPRequest", "HTTPClient", "Supabase"]:
			assert_false(forbidden in source, "%s bypasses its persistence/service boundary with %s" % [path, forbidden])

func _route_params(scene_path: String, policy: Variant = null) -> Dictionary:
	var operations: Array[String] = []
	var journal := RecordingJournalScript.new("access-profile", "access-device", operations)
	var progress := InMemoryProgressServiceScript.new("access-profile", operations)
	var repository := ContentRepositoryScript.new()
	var engine := QuestionEngineScript.new()
	var session := RunSessionScript.new(
		null,
		journal,
		progress,
		func(): return "2026-07-22T00:00:00Z",
		func(): return "access-session-%d" % Time.get_ticks_usec()
	)
	var ui_policy: Variant = policy if policy != null else UiPolicyScript.new()
	ui_policy.set_reduced_motion(true)
	var params := {
		"router": FakeRouter.new(),
		"profile_service": FakeProfileService.new(),
		"profile_activator": null,
		"profile_id": "access-profile",
		"progress_service": progress,
		"journal": journal,
		"content_repository": repository,
		"question_engine": engine,
		"run_session": session,
		"audio_service": FakeAudioService.new(),
		"effects_service": FakeEffectsService.new(),
		"ui_policy": ui_policy,
		"sync_service": OfflineSyncServiceScript.new(journal),
		"activity_id": "foundation_ten_rods",
		"content_version": "a-vertical-1",
		"seed": 42,
		"date": "2026-07-22",
		"result_state": {
			"score": 2,
			"health": 0,
			"earned_rewards": {"apples": 4},
			"completion_reason": "health_depleted",
		},
		"completion_event": {"completion_reason": "health_depleted"},
		"progress_snapshot": {"apples": 4, "pending_review": 3},
		"starting_apples": 0,
	}
	if scene_path != "res://scenes/game/activity_run.tscn":
		params.erase("run_session")
	return params

func _collect_interactives(node: Node, output: Array[Control]) -> void:
	if node is Control and (node is BaseButton or node is LineEdit or node is Range or node.has_signal("accepted")):
		output.append(node)
	for child in node.get_children():
		_collect_interactives(child, output)

func _collect_tactile(node: Node, output: Array[Control]) -> void:
	if node is Control and node.has_signal("accepted") and "reduced_motion" in node:
		output.append(node)
	for child in node.get_children():
		_collect_tactile(child, output)

func _visible_action_label(control: Control) -> String:
	if control is LineEdit:
		return control.placeholder_text
	if control is BaseButton and not control.text.strip_edges().is_empty():
		return control.text
	var text_label := control.find_child("TextLabel", true, false)
	if text_label is Label and not text_label.text.strip_edges().is_empty():
		return text_label.text
	if not control.accessibility_name.strip_edges().is_empty():
		return control.accessibility_name
	var parent := control.get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling is Label and not sibling.text.strip_edges().is_empty():
				return sibling.text
	return ""

func _ancestor_scroll(control: Control) -> ScrollContainer:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return parent
		parent = parent.get_parent()
	return null

func _inside_viewport(control: Control, viewport_size: Vector2i) -> bool:
	var rect := control.get_global_rect()
	const EPSILON := 0.5
	return (
		rect.position.x >= -EPSILON
		and rect.position.y >= -EPSILON
		and rect.end.x <= viewport_size.x + EPSILON
		and rect.end.y <= viewport_size.y + EPSILON
	)

func _contains_network_node(node: Node) -> bool:
	if node.get_class() in ["HTTPRequest", "HTTPClient", "WebSocketPeer", "WebSocketMultiplayerPeer"]:
		return true
	for child in node.get_children():
		if _contains_network_node(child):
			return true
	return false

func _collect_gdscript_sources(path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_collect_gdscript_sources(child, output)
			elif entry.ends_with(".gd"):
				output.append(child)
		entry = directory.get_next()
	directory.list_dir_end()

func _mouse_button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	return event
