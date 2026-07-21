extends "res://tests/support/test_case.gd"

const VIEWPORT_SIZE := Vector2i(360, 800)
const DEFAULT_SETTINGS := {
	"adaptive_difficulty": false,
	"timing_aids": true,
	"timers_enabled": true,
	"reduced_motion": false,
	"effect_quality": "high",
	"master_db": 0.0,
	"music_db": -6.0,
	"sfx_db": 0.0,
	"voice_db": 0.0,
	"voice_enabled": true,
}

class ManyProfiles extends RefCounted:
	var profiles: Array[Dictionary] = []

	func _init() -> void:
		for index in 10:
			profiles.append({
				"profile_id": "profile-%02d" % index,
				"nickname": "Explorer with a long name %02d" % index,
				"avatar_id": "moa_mint",
				"settings": DEFAULT_SETTINGS.duplicate(true),
			})

	func list_profiles() -> Array[Dictionary]:
		return profiles.duplicate(true)

	func get_profile(profile_id: Variant) -> Dictionary:
		for profile in profiles:
			if profile.profile_id == profile_id:
				return profile.duplicate(true)
		return {}

class ManyProgress extends RefCounted:
	func snapshot() -> Dictionary:
		var inventory := {}
		var collections: Array[String] = []
		for index in 12:
			inventory["item_%02d" % index] = index + 1
			collections.append("entry_%02d" % index)
		return {
			"apples": 27,
			"pending_review": 4,
			"inventory": inventory,
			"collections": collections,
		}

class ManyContent extends RefCounted:
	func list_activities() -> Array[Dictionary]:
		var activities: Array[Dictionary] = []
		for index in 8:
			activities.append({
				"activity_id": "activity_%02d" % index,
				"title_key": "activity.foundation_ten_rods.title",
				"description_key": "activity.foundation_ten_rods.description",
				"content_version": "test-%02d" % index,
			})
		return activities

class FakeRouter extends RefCounted:
	func navigate(_route: StringName, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func reset(_route: StringName, _params: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func back() -> bool:
		return true

func run(tree: SceneTree) -> void:
	var services := {
		"router": FakeRouter.new(),
		"profile_service": ManyProfiles.new(),
		"progress_service": ManyProgress.new(),
		"content_repository": ManyContent.new(),
		"profile_id": "profile-00",
		"date": "2026-07-21",
		"online": false,
		"sync_queue_count": 0,
	}
	var prior_locale := TranslationServer.get_locale()
	for locale in ["ko", "en"]:
		TranslationServer.set_locale(locale)
		await _assert_scrollable_scene(tree, "res://scenes/profile/profile_select.tscn", services, _profile_targets())
		await _assert_scrollable_scene(tree, "res://scenes/island/free_play.tscn", services, _activity_targets())
		await _assert_scrollable_scene(tree, "res://scenes/island/inventory.tscn", services, _inventory_targets())
		await _assert_scrollable_scene(tree, "res://scenes/island/collection.tscn", services, _collection_targets())
		await _assert_scrollable_scene(tree, "res://scenes/island/settings.tscn", services, _settings_targets())
	TranslationServer.set_locale(prior_locale)

func _assert_scrollable_scene(tree: SceneTree, scene_path: String, services: Dictionary, target_names: Array[String]) -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	tree.root.add_child(viewport)
	var screen: Control = load(scene_path).instantiate()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.configure(services)
	viewport.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	var scroll: ScrollContainer = screen.find_child("BodyScroll", true, false)
	assert_not_null(scroll, "%s must expose BodyScroll" % scene_path)
	if scroll == null:
		viewport.queue_free()
		await tree.process_frame
		return
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s must not scroll horizontally" % scene_path)
	var body: Control = screen.find_child("Body", true, false)
	assert_not_null(body)
	if body != null:
		assert_true(body.size.x <= scroll.size.x + 0.5, "%s content width overflows: body=%s scroll=%s" % [scene_path, body.size, scroll.size])
	for target_name in target_names:
		var target: Control = screen.find_child(target_name, true, false)
		assert_not_null(target, "%s is missing %s" % [scene_path, target_name])
		if target == null:
			continue
		if scroll.is_ancestor_of(target):
			scroll.ensure_control_visible(target)
			await tree.process_frame
			await tree.process_frame
		assert_true(target.is_visible_in_tree(), "%s is hidden" % target_name)
		if _is_interactive(target):
			assert_true(target.size.x >= 48.0 and target.size.y >= 48.0, "%s is smaller than 48px" % target_name)
		assert_true(_rect_inside(target.get_global_rect(), Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))), "%s clips after ensure_control_visible: %s" % [target_name, target.get_global_rect()])
		assert_true(target.get_global_rect().position.x >= -0.5 and target.get_global_rect().end.x <= VIEWPORT_SIZE.x + 0.5, "%s overflows horizontally" % target_name)
	viewport.queue_free()
	await tree.process_frame

func _profile_targets() -> Array[String]:
	var result: Array[String] = ["ProfilePinInput", "UnlockButton", "CreateProfileButton"]
	for index in 10:
		result.append("ProfileButton_%d" % index)
	return result

func _activity_targets() -> Array[String]:
	var result: Array[String] = ["BackButton"]
	for index in 8:
		result.append("ActivityButton_%d" % index)
	return result

func _inventory_targets() -> Array[String]:
	var result: Array[String] = ["BackButton"]
	for index in 12:
		result.append("Inventory_item_%02d" % index)
	return result

func _collection_targets() -> Array[String]:
	var result: Array[String] = ["BackButton"]
	for index in 12:
		result.append("Collection_entry_%02d" % index)
	return result

func _settings_targets() -> Array[String]:
	return [
		"BackButton",
		"AdaptiveToggle",
		"TimingAidsToggle",
		"TimersToggle",
		"ReducedMotionToggle",
		"EffectQualityOption",
		"VoiceEnabledToggle",
		"MasterVolume",
		"MusicVolume",
		"SfxVolume",
		"VoiceVolume",
	]

func _is_interactive(control: Control) -> bool:
	return control is BaseButton or control is LineEdit or control is Range or control.has_signal("accepted")

func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	const EPSILON := 0.5
	return (
		inner.position.x >= outer.position.x - EPSILON
		and inner.position.y >= outer.position.y - EPSILON
		and inner.end.x <= outer.end.x + EPSILON
		and inner.end.y <= outer.end.y + EPSILON
	)
