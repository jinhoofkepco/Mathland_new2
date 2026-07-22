extends "res://tests/support/test_case.gd"

const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const ProfileCreateDialogScene = preload("res://scenes/profile/profile_create_dialog.tscn")
const DailyObjectiveServiceScript = preload("res://src/island/daily_objective_service.gd")

const VIEWPORT_SIZES := [Vector2i(360, 800), Vector2i(1080, 2400), Vector2i(800, 1280)]
const SCREEN_CASES := {
	"res://scenes/profile/profile_select.tscn": ["CreateProfileButton", "UnlockButton"],
	"res://scenes/island/exploration_island.tscn": [
		"HomeVoiceButton",
		"ContinueButton",
		"DailyPathButton",
		"FreePlayButton",
		"InventoryButton",
		"CollectionButton",
		"SettingsButton",
		"SwitchProfileButton",
	],
	"res://scenes/island/daily_path.tscn": ["StartFirstObjectiveButton", "BackButton"],
	"res://scenes/island/free_play.tscn": ["ActivityButton_0", "BackButton"],
	"res://scenes/island/inventory.tscn": ["BackButton"],
	"res://scenes/island/collection.tscn": ["BackButton"],
	"res://scenes/island/settings.tscn": ["BackButton"],
}

const PROFILE_BASE_PATH := "user://tests/child_shell_profiles"

class FakeRouter extends RefCounted:
	var calls: Array[Dictionary] = []

	func navigate(route: StringName, params: Dictionary = {}) -> Dictionary:
		calls.append({"route": route, "params": params.duplicate(true)})
		return {"ok": true}

	func back() -> bool:
		calls.append({"route": &"back", "params": {}, "mode": "back"})
		return true

	func reset(route: StringName, params: Dictionary = {}) -> Dictionary:
		calls.append({"route": route, "params": params.duplicate(true), "mode": "reset"})
		return {"ok": true}

class FakeActivator extends RefCounted:
	var calls: Array[Dictionary] = []
	var result: Dictionary = {"ok": false, "error": "activation_failed"}

	func activate_profile(profile_id: String, pin: String, now_unix: int) -> Dictionary:
		calls.append({"profile_id": profile_id, "pin": pin, "now_unix": now_unix})
		return result.duplicate(true)

class FakeProgressService extends RefCounted:
	func snapshot() -> Dictionary:
		return {
			"apples": 27,
			"pending_review": 4,
			"inventory": {"shell": 2, "compass": 1},
			"collections": ["first_map"],
		}

class FakeContentRepository extends RefCounted:
	func list_activities() -> Array[Dictionary]:
		return [{
			"activity_id": "foundation_ten_rods",
			"title": "열 묶음 탐험",
			"description": "열 막대를 움직여 수를 만들어요.",
			"content_version": "test-1",
		}, {
			"activity_id": "future_unmapped_activity",
			"title": "미래 탐험",
			"description": "새로운 수학 보물을 찾아요.",
			"content_version": "test-1",
		}]

class FakeAudioService extends RefCounted:
	var applied: Array[Dictionary] = []
	var sfx: Array[StringName] = []
	var toggled_voice: Array[StringName] = []

	func apply_settings(settings: Dictionary) -> bool:
		applied.append(settings.duplicate(true))
		return true

	func play_sfx(sfx_id: StringName) -> bool:
		sfx.append(sfx_id)
		return true

	func play_policy_voice(_policy: StringName, _context: Dictionary = {}, _authorized := false) -> bool:
		return false

	func dialogue_for_policy(policy: StringName, _context: Dictionary = {}) -> StringName:
		return &"moa_home_welcome" if policy == &"first_home" else &""

	func toggle_voice(dialogue_id: StringName) -> bool:
		toggled_voice.append(dialogue_id)
		return true

class FakeEffectsService extends RefCounted:
	var policies: Array[Dictionary] = []

	func set_policy(quality: StringName, reduced_motion: bool) -> bool:
		policies.append({"quality": quality, "reduced_motion": reduced_motion})
		return true

class FakePairingSyncService extends RefCounted:
	signal status_changed(status: Dictionary)

	var calls: Array[Dictionary] = []
	var re_pair_calls: Array[Dictionary] = []
	var next_result := {"ok": true, "family_id": "family-1"}
	var next_re_pair_result := {"ok": true, "family_id": "family-1"}
	var current_status := {"state": "offline", "pending_count": 3, "last_success_at": null}

	func pair_device(code: String, profile_id: String, display_name: String) -> Dictionary:
		calls.append({"code": code, "profile_id": profile_id, "display_name": display_name})
		return next_result.duplicate(true)

	func status() -> Dictionary:
		return current_status.duplicate(true)

	func publish_status(next_status: Dictionary) -> void:
		current_status = next_status.duplicate(true)
		status_changed.emit(current_status.duplicate(true))

	func re_pair_device(code: String, profile_id: String, display_name: String) -> Dictionary:
		re_pair_calls.append({"code": code, "profile_id": profile_id, "display_name": display_name})
		return next_re_pair_result.duplicate(true)

func run(tree: SceneTree) -> void:
	_cleanup_profile_files()
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new(PROFILE_BASE_PATH))
	var created := profile_service.create_profile("모아", "moa_mint", "1234")
	assert_true(created.ok)
	var services := {
		"router": FakeRouter.new(),
		"profile_service": profile_service,
		"progress_service": FakeProgressService.new(),
		"content_repository": FakeContentRepository.new(),
		"audio_service": FakeAudioService.new(),
		"effects_service": FakeEffectsService.new(),
		"sync_service": FakePairingSyncService.new(),
		"profile_id": created.profile.profile_id,
		"date": "2026-07-21",
		"online": false,
		"sync_queue_count": 3,
	}
	var ui_policy_path := "res://src/ui/shared/ui_policy.gd"
	assert_true(ResourceLoader.exists(ui_policy_path), "UI policy service is missing")
	if ResourceLoader.exists(ui_policy_path):
		var UiPolicyScript: Variant = load(ui_policy_path)
		services["ui_policy"] = UiPolicyScript.new()
	await _test_all_screens_at_supported_viewports(tree, services)
	await _test_profile_creation_rules(tree, profile_service)
	await _test_profile_tactile_audio_is_wired_through_nested_dialog(tree, services)
	await _test_profile_activation_gates_route(tree, profile_service, services)
	await _test_island_data_and_routes(tree, services)
	await _test_collection_release_art(tree, services)
	await _test_free_play_release_activity_icon(tree, services)
	await _test_offline_copy_is_explicit(tree, services)
	await _test_island_sync_status_reacts_and_disconnects(tree, services)
	await _test_settings_are_profile_scoped_and_live(tree, services)
	await _test_reduced_motion_reaches_current_and_new_buttons(tree, services)
	_test_daily_objectives_are_stable_and_distinct()
	(services.router as FakeRouter).calls.clear()
	services.clear()
	profile_service.free()
	await tree.process_frame
	_cleanup_profile_files()

func _test_all_screens_at_supported_viewports(tree: SceneTree, services: Dictionary) -> void:
	var prior_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("ko")
	for viewport_size in VIEWPORT_SIZES:
		for scene_path in SCREEN_CASES:
			var packed: Variant = load(scene_path)
			assert_true(packed is PackedScene, "missing screen: %s" % scene_path)
			if not packed is PackedScene:
				continue
			var viewport := SubViewport.new()
			viewport.size = viewport_size
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			tree.root.add_child(viewport)
			var screen: Control = packed.instantiate()
			screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if screen.has_method("configure"):
				screen.configure(services)
			viewport.add_child(screen)
			await tree.process_frame
			await tree.process_frame
			assert_eq(screen.size, Vector2(viewport_size), "%s did not fill %s" % [scene_path, viewport_size])
			var scroll: ScrollContainer = screen.find_child("BodyScroll", true, false)
			for action_name in SCREEN_CASES[scene_path]:
				var action: Control = screen.find_child(action_name, true, false)
				assert_not_null(action, "%s is missing %s" % [scene_path, action_name])
				if action == null:
					continue
				if scroll != null and scroll.is_ancestor_of(action):
					scroll.ensure_control_visible(action)
					await tree.process_frame
					await tree.process_frame
				assert_true(action.is_visible_in_tree(), "%s is hidden" % action_name)
				assert_true(action.size.x >= 48.0 and action.size.y >= 48.0, "%s has a small target" % action_name)
				assert_true(_rect_inside(action.get_global_rect(), Rect2(Vector2.ZERO, Vector2(viewport_size))), "%s clips at %s" % [action_name, viewport_size])
				var visible_text := _action_text(action)
				assert_false(visible_text.strip_edges().is_empty(), "%s has no visible label" % action_name)
				assert_false(visible_text.begins_with("ui."), "%s exposes an untranslated key" % action_name)
			viewport.queue_free()
			await tree.process_frame
	TranslationServer.set_locale(prior_locale)

func _test_profile_creation_rules(tree: SceneTree, profile_service: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var dialog: Control = ProfileCreateDialogScene.instantiate()
	dialog.configure({"profile_service": profile_service})
	viewport.add_child(dialog)
	await tree.process_frame
	assert_eq(dialog.submit_values(" 모아 ", "moa_sky", "5678").error, "duplicate_nickname")
	assert_eq(dialog.submit_values("새별", "moa_sky", "12가4").error, "invalid_pin")
	assert_eq(dialog.submit_values("새별", "unknown", "5678").error, "invalid_avatar")
	var case_variant: Dictionary = dialog.submit_values("모아A", "moa_sky", "5678")
	assert_true(case_variant.ok, "only an exact normalized nickname match may be rejected")
	viewport.queue_free()
	await tree.process_frame

func _test_profile_tactile_audio_is_wired_through_nested_dialog(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/profile/profile_select.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	var audio := services.audio_service as FakeAudioService
	audio.sfx.clear()
	for button_name in ["ProfileButton_0", "UnlockButton", "CreateProfileButton"]:
		var button: Control = screen.find_child(button_name, true, false)
		assert_not_null(button, "%s is missing from ProfileSelect" % button_name)
		if button != null:
			_tap_tactile(button)
	var dialog: Control = screen.find_child("CreateProfileDialog", true, false)
	assert_true(dialog.visible, "CreateProfileButton did not open the nested dialog")
	var close_button: Control = dialog.find_child("CloseButton", true, false)
	assert_not_null(close_button)
	if close_button != null:
		_tap_tactile(close_button)
	screen.show_create_dialog()
	var save_button: Control = dialog.find_child("SaveProfileButton", true, false)
	assert_not_null(save_button)
	if save_button != null:
		_tap_tactile(save_button)
	assert_eq(audio.sfx, [
		&"button_down", &"button_release",
		&"button_down", &"button_release",
		&"button_down", &"button_release",
		&"button_down", &"button_release",
		&"button_down", &"button_release",
	], "ProfileSelect and ProfileCreateDialog must share production tactile audio")
	viewport.queue_free()
	await tree.process_frame

func _test_profile_activation_gates_route(tree: SceneTree, profile_service: Node, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/profile/profile_select.tscn")
	var screen: Control = scene.instantiate()
	var router := FakeRouter.new()
	var activator := FakeActivator.new()
	var params := services.duplicate(false)
	params.router = router
	params.profile_activator = activator
	screen.configure(params)
	viewport.add_child(screen)
	await tree.process_frame
	var profile_id: String = profile_service.list_profiles()[0].profile_id
	var failed: Dictionary = screen.attempt_unlock(profile_id, "1234", 1000)
	assert_false(failed.ok)
	assert_eq(router.calls, [], "failed activation must not route")
	activator.result = {
		"ok": true,
		"profile": profile_service.get_profile(profile_id),
		"route_params": {"profile_id": profile_id, "progress_service": services.progress_service},
	}
	var activated: Dictionary = screen.attempt_unlock(profile_id, "1234", 1001)
	assert_true(activated.ok)
	assert_eq(activator.calls.size(), 2)
	assert_eq(router.calls.back().route, &"island")
	viewport.queue_free()
	await tree.process_frame
	router.calls.clear()
	activator.calls.clear()

func _test_island_data_and_routes(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/exploration_island.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	assert_eq(screen.objective_keys().size(), 3)
	assert_eq(screen.objective_keys().duplicate().reduce(func(unique, key):
		if key not in unique:
			unique.append(key)
		return unique
	, []).size(), 3)
	assert_eq(screen.apple_balance(), 27)
	assert_eq(screen.pending_review_count(), 4)
	assert_eq(screen.sync_state(), {"online": false, "queued": 3})
	var background: TextureRect = screen.find_child("ExplorationIslandBackground", true, false)
	assert_not_null(background)
	if background != null:
		assert_true(background.texture is Texture2D)
		assert_eq(background.size, screen.size)
		if background.texture != null:
			assert_eq(background.texture.resource_path, "res://assets/art/island/exploration_island_bg.png")
	var home_voice: Control = screen.find_child("HomeVoiceButton", true, false)
	assert_not_null(home_voice, "first-home voice has no visible replay/stop control")
	if home_voice != null:
		assert_true(home_voice.is_visible_in_tree())
		home_voice.accepted.emit()
		assert_eq((services.audio_service as FakeAudioService).toggled_voice.back(), &"moa_home_welcome")
	screen.open_daily_path()
	assert_eq((services.router as FakeRouter).calls.back().route, &"daily_path")
	screen.switch_profile()
	assert_eq((services.router as FakeRouter).calls.back().route, &"profile_select")
	assert_eq((services.router as FakeRouter).calls.back().mode, "reset")
	viewport.queue_free()
	await tree.process_frame

func _test_collection_release_art(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/collection.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	var artwork: TextureRect = screen.find_child("CollectionArt_first_map", true, false)
	assert_not_null(artwork)
	if artwork != null:
		assert_true(artwork.texture is AtlasTexture)
		assert_true(artwork.is_visible_in_tree())
		assert_true(artwork.size.x > 0.0 and artwork.size.y > 0.0)
		if artwork.texture is AtlasTexture:
			assert_eq(artwork.texture.atlas.resource_path, "res://assets/art/collection/collection_shells.png")
			assert_eq(artwork.texture.region, Rect2(64, 304, 480, 480))
	var name_label: Label = screen.find_child("CollectionName_first_map", true, false)
	assert_not_null(name_label)
	if name_label != null:
		assert_false(name_label.text.strip_edges().is_empty())
		assert_ne(name_label.text, "collection.first_map")
	viewport.queue_free()
	await tree.process_frame

func _test_free_play_release_activity_icon(tree: SceneTree, services: Dictionary) -> void:
	(services.router as FakeRouter).calls.clear()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/free_play.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	var button: Control = screen.find_child("ActivityButton_0", true, false)
	assert_not_null(button)
	if button != null:
		var icon: TextureRect = button.get_node("Visual/Content/IconTexture")
		assert_true(icon.visible)
		assert_true(icon.texture is Texture2D)
		if icon.texture != null:
			assert_eq(icon.texture.resource_path, "res://assets/ui/icons/activities/foundations_base_ten.svg")
		assert_eq(button.get_node("Visual/Content/TextLabel").text, "열 묶음 탐험")
		assert_false(button.get_node("Visual/Content/TextLabel").text.begins_with("activity."))
		assert_false(button.accessibility_name.strip_edges().is_empty())
		var card: Control = screen.find_child("ActivityCard_0", true, false)
		assert_not_null(card)
		if card != null:
			for child in card.find_children("*", "Label", true, false):
				assert_false(String(child.text).begins_with("activity."), "Free Play exposed a raw localization key")
		_tap_tactile(button)
		var routed: Dictionary = (services.router as FakeRouter).calls.back()
		assert_eq(routed.get("route"), &"activity_run")
		assert_eq(routed.get("params", {}).get("source"), "free_play")
		assert_eq(routed.get("params", {}).get("activity_id"), "foundation_ten_rods")
		assert_eq(
			routed.get("params", {}).get("content_version"),
			"test-1",
			"Free Play must pin the active package version into its activity route",
		)
	var fallback_button: Control = screen.find_child("ActivityButton_1", true, false)
	assert_not_null(fallback_button)
	if fallback_button != null:
		var fallback_texture: TextureRect = fallback_button.get_node("Visual/Content/IconTexture")
		var fallback_glyph: Label = fallback_button.get_node("Visual/Content/IconLabel")
		assert_false(fallback_texture.visible)
		assert_true(fallback_glyph.visible)
		assert_eq(fallback_glyph.text, "›", "unmapped activities must preserve arrow_right")
	viewport.queue_free()
	await tree.process_frame

func _test_offline_copy_is_explicit(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/exploration_island.tscn")
	var zero_params := services.duplicate(false)
	zero_params.erase("sync_service")
	zero_params.online = false
	zero_params.sync_queue_count = 0
	var zero_screen: Control = scene.instantiate()
	zero_screen.configure(zero_params)
	viewport.add_child(zero_screen)
	await tree.process_frame
	assert_eq(zero_screen.sync_status_text(), TranslationServer.translate("sync.offline"))
	zero_screen.queue_free()
	await tree.process_frame
	var queued_params := services.duplicate(false)
	queued_params.erase("sync_service")
	queued_params.online = false
	queued_params.sync_queue_count = 3
	var queued_screen: Control = scene.instantiate()
	queued_screen.configure(queued_params)
	viewport.add_child(queued_screen)
	await tree.process_frame
	assert_eq(queued_screen.sync_status_text(), TranslationServer.translate("sync.offline_queued") % 3)
	viewport.queue_free()
	await tree.process_frame

func _test_island_sync_status_reacts_and_disconnects(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/exploration_island.tscn")
	var reactive_sync := FakePairingSyncService.new()
	reactive_sync.current_status = {"state": "connecting", "pending_count": 2, "last_success_at": null}
	var params := services.duplicate(false)
	params.sync_service = reactive_sync
	var screen: Control = scene.instantiate()
	screen.configure(params)
	viewport.add_child(screen)
	await tree.process_frame
	var callback := Callable(screen, "_on_sync_status_changed")
	assert_true(reactive_sync.status_changed.is_connected(callback), "island did not subscribe to live sync status")
	assert_eq(screen.sync_status_text(), TranslationServer.translate("sync.connecting"))
	assert_ne(screen.sync_status_text(), "sync.connecting", "connecting copy is missing from translations")
	var sync_label: Label = screen.find_child("SyncStateLabel", true, false)
	assert_not_null(sync_label)
	if sync_label != null:
		assert_eq(sync_label.text, screen.sync_status_text())
	reactive_sync.publish_status({"state": "syncing", "pending_count": 2, "last_success_at": null})
	await tree.process_frame
	assert_eq(screen.sync_status_text(), TranslationServer.translate("sync.connecting"))
	reactive_sync.publish_status({
		"state": "suspended",
		"pending_count": 2,
		"last_success_at": null,
		"diagnostic": "re_pair_required",
	})
	await tree.process_frame
	assert_eq(screen.sync_status_text(), TranslationServer.translate("sync.re_pair_required"))
	assert_ne(screen.sync_status_text(), "sync.re_pair_required")
	reactive_sync.publish_status({"state": "online", "pending_count": 0, "last_success_at": "2026-07-22T01:02:03Z"})
	await tree.process_frame
	assert_eq(screen.sync_state(), {"online": true, "queued": 0})
	assert_eq(screen.sync_status_text(), TranslationServer.translate("sync.online"))
	if sync_label != null:
		assert_eq(sync_label.text, TranslationServer.translate("sync.online"))
	screen.queue_free()
	await tree.process_frame
	assert_false(reactive_sync.status_changed.is_connected(callback), "island retained a stale sync subscription")
	viewport.queue_free()
	await tree.process_frame

func _test_settings_are_profile_scoped_and_live(tree: SceneTree, services: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/settings.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	assert_false(screen.current_settings().adaptive_difficulty, "adaptive difficulty must default off")
	assert_true(screen.apply_setting("adaptive_difficulty", true))
	assert_true(screen.apply_setting("voice_enabled", false))
	assert_true(screen.apply_setting("effect_quality", "low"))
	assert_true(screen.apply_setting("reduced_motion", true))
	assert_true(screen.apply_setting("music_db", -18.0))
	var stored: Dictionary = services.profile_service.get_profile(services.profile_id).settings
	assert_true(stored.adaptive_difficulty)
	assert_false(stored.voice_enabled)
	assert_eq(stored.effect_quality, "low")
	assert_true(stored.reduced_motion)
	assert_eq(stored.music_db, -18.0)
	assert_true((services.audio_service as FakeAudioService).applied.size() >= 2)
	assert_eq((services.effects_service as FakeEffectsService).policies.back(), {"quality": &"low", "reduced_motion": true})
	if services.has("ui_policy"):
		assert_true(services.ui_policy.reduced_motion_enabled())
		var back_button: Control = screen.find_child("BackButton", true, false)
		assert_true(back_button.reduced_motion, "current tactile button must update immediately")
	var code_input: LineEdit = screen.find_child("PairingCodeInput", true, false)
	var pair_button: Control = screen.find_child("PairDeviceButton", true, false)
	var pairing_status: Label = screen.find_child("PairingStatus", true, false)
	assert_not_null(code_input)
	assert_not_null(pair_button)
	assert_not_null(pairing_status)
	if code_input != null and pair_button != null and pairing_status != null:
		assert_eq(code_input.max_length, 6)
		var invalid_result: Dictionary = await screen.submit_pairing_code("12x456")
		assert_eq(invalid_result.get("error"), "invalid_pairing_code")
		assert_eq((services.sync_service as FakePairingSyncService).calls, [])
		var valid_result: Dictionary = await screen.submit_pairing_code("123456")
		assert_true(valid_result.ok)
		assert_eq((services.sync_service as FakePairingSyncService).calls.back(), {
			"code": "123456",
			"profile_id": services.profile_id,
			"display_name": "모아",
		})
		assert_eq(code_input.text, "", "one-use pairing code must not remain in the UI")
		assert_false(pairing_status.text.strip_edges().is_empty())
		var sync_service := services.sync_service as FakePairingSyncService
		sync_service.next_result = {"ok": false, "error": "re_pair_required"}
		var re_pair_required: Dictionary = await screen.submit_pairing_code("654321")
		assert_eq(re_pair_required.get("error"), "re_pair_required")
		assert_eq(pairing_status.text, TranslationServer.translate("settings.pairing.re_pair_required"))
		var re_pair_button: Control = screen.find_child("RePairDeviceButton", true, false)
		assert_not_null(re_pair_button)
		if re_pair_button != null:
			assert_true(re_pair_button.visible)
		assert_true(screen.has_method("confirm_re_pair"))
		if screen.has_method("confirm_re_pair"):
			var re_paired: Dictionary = await screen.confirm_re_pair()
			assert_true(re_paired.ok)
			assert_eq(sync_service.re_pair_calls.back(), {
				"code": "654321",
				"profile_id": services.profile_id,
				"display_name": "모아",
			})
			if re_pair_button != null:
				assert_false(re_pair_button.visible)
		sync_service.next_result = {"ok": true, "family_id": "family-1"}
	viewport.queue_free()
	await tree.process_frame

func _test_reduced_motion_reaches_current_and_new_buttons(tree: SceneTree, services: Dictionary) -> void:
	if not services.has("ui_policy"):
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var scene: PackedScene = load("res://scenes/island/exploration_island.tscn")
	var screen: Control = scene.instantiate()
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	var continue_button: Control = screen.find_child("ContinueButton", true, false)
	assert_true(continue_button.reduced_motion, "new tactile controls must inherit profile policy")
	viewport.queue_free()
	await tree.process_frame

func _test_daily_objectives_are_stable_and_distinct() -> void:
	var service := DailyObjectiveServiceScript.new()
	var first: Array[Dictionary] = service.objectives("profile-a", "2026-07-21")
	var repeated: Array[Dictionary] = service.objectives("profile-a", "2026-07-21")
	var other_profile: Array[Dictionary] = service.objectives("profile-b", "2026-07-21")
	assert_eq(first, repeated)
	assert_eq(first.size(), 3)
	var keys := first.map(func(objective): return objective.objective_id)
	var unique := []
	for key in keys:
		if key not in unique:
			unique.append(key)
	assert_eq(unique.size(), 3)
	assert_ne(first, other_profile)
	assert_eq(service.objectives("", "2026-07-21"), [])
	assert_eq(service.objectives("profile-a", "not-a-date"), [])

func _action_text(action: Control) -> String:
	if action is BaseButton:
		return action.text
	var text_label := action.find_child("TextLabel", true, false)
	return text_label.text if text_label is Label else ""

func _tap_tactile(button: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = button.size * 0.5
	button._gui_input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = button.size * 0.5
	button._gui_input(up)

func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	const EPSILON := 0.5
	return (
		inner.position.x >= outer.position.x - EPSILON
		and inner.position.y >= outer.position.y - EPSILON
		and inner.end.x <= outer.end.x + EPSILON
		and inner.end.y <= outer.end.y + EPSILON
	)

func _cleanup_profile_files() -> void:
	for file_name in ["profiles.json", "profiles.json.tmp", "profiles.json.bak"]:
		var path := "%s/%s" % [PROFILE_BASE_PATH, file_name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
