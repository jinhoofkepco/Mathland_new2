extends "res://tests/support/test_case.gd"

const EffectCatalogScript = preload("res://src/presentation/effects/effect_catalog.gd")
const EffectsServiceScript = preload("res://src/presentation/effects/effects_service.gd")

const EXPECTED_NAMES: Array[StringName] = [
	&"correct",
	&"wrong",
	&"combo_1",
	&"combo_2",
	&"boss",
	&"health_loss",
	&"target_reached",
	&"level_up",
	&"health_depleted",
	&"reward",
	&"collection",
	&"coupon",
]

func run(tree: SceneTree) -> void:
	await _test_catalog_is_complete_and_isolated(tree)
	await _test_quality_reduced_motion_and_unknown_names(tree)
	await _test_sequential_effects_reuse_prewarmed_nodes(tree)

func _test_catalog_is_complete_and_isolated(tree: SceneTree) -> void:
	var catalog := EffectCatalogScript.new()
	assert_eq(catalog.names(), EXPECTED_NAMES)
	for effect_name in EXPECTED_NAMES:
		var preset: Dictionary = catalog.get_preset(effect_name)
		assert_false(preset.is_empty(), "%s is missing" % effect_name)
		assert_true(preset.particle_count > 0)
		assert_true(preset.flash_duration > 0.0)
	var leaked: Dictionary = catalog.get_preset(&"correct")
	leaked.particle_count = 9999
	assert_ne(catalog.get_preset(&"correct").particle_count, 9999, "catalog presets leaked mutable state")
	assert_eq(catalog.get_preset(&"unknown"), {})
	await tree.process_frame

func _test_quality_reduced_motion_and_unknown_names(tree: SceneTree) -> void:
	var service = EffectsServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	for effect_name in EXPECTED_NAMES:
		assert_true(service.play(effect_name, Vector2.ZERO), "%s did not resolve through EffectsService" % effect_name)
		service.latest_burst().finish_now()
	assert_true(service.set_policy(&"high", false))
	assert_true(service.play(&"correct", Vector2(20, 30)))
	var high_burst = service.latest_burst()
	var high_particles: int = high_burst.configured_particle_count
	high_burst.finish_now()
	assert_true(service.set_policy(&"low", false))
	assert_true(service.play(&"correct", Vector2(40, 50)))
	var low_burst = service.latest_burst()
	assert_true(low_burst.configured_particle_count <= high_particles / 4)
	low_burst.finish_now()
	assert_true(service.set_policy(&"high", true))
	assert_true(service.play(&"boss", Vector2(60, 70)))
	var reduced_burst = service.latest_burst()
	assert_eq(reduced_burst.configured_shake_amplitude, 0.0)
	assert_eq(reduced_burst.configured_translation_amplitude, 0.0)
	assert_true(reduced_burst.configured_flash_duration > 0.0)
	reduced_burst.finish_now()
	var created_before: int = service.total_created()
	assert_false(service.play(&"not_a_preset", Vector2.ZERO))
	assert_eq(service.total_created(), created_before)
	assert_false(service.set_policy(&"ultra", false))
	service.queue_free()
	await tree.process_frame

func _test_sequential_effects_reuse_prewarmed_nodes(tree: SceneTree) -> void:
	var service = EffectsServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	assert_eq(service.total_created(), 8)
	var instance_ids: Array[int] = []
	for index in 10:
		assert_true(service.play(&"reward", Vector2(index * 10, 0)))
		var burst = service.latest_burst()
		instance_ids.append(burst.get_instance_id())
		burst.finish_now()
	assert_eq(service.total_created(), 8, "sequential effects grew beyond the prewarmed pool")
	assert_eq(service.active_count(), 0)
	assert_eq(service.available_count(), 8)
	assert_true(instance_ids[0] in instance_ids.slice(1), "no prewarmed burst was reused")
	service.queue_free()
	await tree.process_frame
