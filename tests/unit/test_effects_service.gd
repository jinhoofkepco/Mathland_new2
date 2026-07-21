extends "res://tests/support/test_case.gd"

const EffectCatalogScript = preload("res://src/presentation/effects/effect_catalog.gd")
const EffectsServiceScript = preload("res://src/presentation/effects/effects_service.gd")
const TransientPoolScript = preload("res://src/presentation/effects/transient_pool.gd")
const EffectBurstScene = preload("res://scenes/shared/effect_burst.tscn")

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
	await _test_failed_pool_configuration_rolls_back_and_can_retry(tree)
	await _test_quality_reduced_motion_and_unknown_names(tree)
	await _test_natural_completion_returns_to_pool_and_reuses_instance(tree)
	await _test_sequential_effects_reuse_prewarmed_nodes(tree)

func _test_catalog_is_complete_and_isolated(tree: SceneTree) -> void:
	var catalog := EffectCatalogScript.new()
	assert_eq(catalog.names(), EXPECTED_NAMES)
	for effect_name in EXPECTED_NAMES:
		var preset: Dictionary = catalog.get_preset(effect_name)
		assert_false(preset.is_empty(), "%s is missing" % effect_name)
		assert_true(preset.particle_count > 0)
		assert_true(preset.flash_duration > 0.0)
		assert_true(preset.has("label_key"), "%s is missing its translation key" % effect_name)
		assert_false(preset.has("label"), "%s leaked literal gameplay copy" % effect_name)
		if preset.has("label_key"):
			assert_eq(preset.label_key, StringName("effect.%s.caption" % str(effect_name)))
	var leaked: Dictionary = catalog.get_preset(&"correct")
	leaked.particle_count = 9999
	assert_ne(catalog.get_preset(&"correct").particle_count, 9999, "catalog presets leaked mutable state")
	assert_eq(catalog.get_preset(&"unknown"), {})
	await tree.process_frame

func _test_failed_pool_configuration_rolls_back_and_can_retry(tree: SceneTree) -> void:
	var invalid_scene := PackedScene.new()
	var invalid_root := Node.new()
	assert_eq(invalid_scene.pack(invalid_root), OK)
	invalid_root.free()
	var pool = TransientPoolScript.new()
	tree.root.add_child(pool)
	await tree.process_frame
	assert_false(pool.configure(invalid_scene, 8))
	assert_eq(pool.get_child_count(), 0, "failed prewarm retained children")
	assert_eq(pool.total_created(), 0, "failed prewarm retained its creation count")
	assert_eq(pool.available_count(), 0, "failed prewarm retained available instances")
	assert_eq(pool.active_count(), 0, "failed prewarm retained active instances")
	assert_true(pool.configure(EffectBurstScene, 8), "failed configuration prevented a valid retry")
	assert_eq(pool.get_child_count(), 8)
	assert_eq(pool.total_created(), 8)
	assert_eq(pool.available_count(), 8)
	pool.queue_free()
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

func _test_natural_completion_returns_to_pool_and_reuses_instance(tree: SceneTree) -> void:
	var service = EffectsServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	assert_eq(service.total_created(), 8)
	assert_true(service.play(&"wrong", Vector2.ZERO))
	var first_burst = service.latest_burst()
	var first_instance_id: int = first_burst.get_instance_id()
	assert_eq(service.active_count(), 1)
	assert_eq(service.available_count(), 7)
	await tree.create_timer(0.4).timeout
	assert_false(first_burst.active, "natural completion did not finish the burst")
	assert_eq(service.active_count(), 0, "natural completion did not release the burst")
	assert_eq(service.available_count(), 8)
	assert_eq(service.total_created(), 8)
	assert_true(service.play(&"wrong", Vector2.ZERO))
	assert_eq(service.latest_burst().get_instance_id(), first_instance_id, "naturally completed burst was not reused")
	service.latest_burst().finish_now()
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
