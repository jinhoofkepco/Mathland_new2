extends "res://tests/support/test_case.gd"

const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const ProfileCreateDialogScene = preload("res://scenes/profile/profile_create_dialog.tscn")
const DailyObjectiveServiceScript = preload("res://src/island/daily_objective_service.gd")

const VIEWPORT_SIZES := [Vector2i(360, 800), Vector2i(1080, 2400), Vector2i(800, 1280)]
const SCREEN_CASES := {
	"res://scenes/profile/profile_select.tscn": ["CreateProfileButton", "UnlockButton"],
	"res://scenes/island/exploration_island.tscn": [
		"ContinueButton",
		"DailyPathButton",
		"FreePlayButton",
		"InventoryButton",
		"CollectionButton",
		"SettingsButton",
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
		calls.append({"route": &"back", "params": {}})
		return true

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
			"title_key": "activity.foundation_ten_rods.title",
			"description_key": "activity.foundation_ten_rods.description",
			"content_version": "test-1",
		}]

class FakeAudioService extends RefCounted:
	var applied: Array[Dictionary] = []

	func apply_settings(settings: Dictionary) -> bool:
		applied.append(settings.duplicate(true))
		return true

class FakeEffectsService extends RefCounted:
	var policies: Array[Dictionary] = []

	func set_policy(quality: StringName, reduced_motion: bool) -> bool:
		policies.append({"quality": quality, "reduced_motion": reduced_motion})
		return true

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
		"profile_id": created.profile.profile_id,
		"date": "2026-07-21",
		"online": false,
		"sync_queue_count": 3,
	}
	await _test_all_screens_at_supported_viewports(tree, services)
	await _test_profile_creation_rules(tree, profile_service)
	await _test_island_data_and_routes(tree, services)
	await _test_settings_are_profile_scoped_and_live(tree, services)
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
			for action_name in SCREEN_CASES[scene_path]:
				var action: Control = screen.find_child(action_name, true, false)
				assert_not_null(action, "%s is missing %s" % [scene_path, action_name])
				if action == null:
					continue
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
	screen.open_daily_path()
	assert_eq((services.router as FakeRouter).calls.back().route, &"daily_path")
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
