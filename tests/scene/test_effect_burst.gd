extends "res://tests/support/test_case.gd"

const EffectBurstScene = preload("res://scenes/shared/effect_burst.tscn")

func run(tree: SceneTree) -> void:
	await _test_burst_plays_and_finishes(tree)
	await _test_reduced_motion_preserves_flash(tree)

func _test_burst_plays_and_finishes(tree: SceneTree) -> void:
	var burst = EffectBurstScene.instantiate()
	tree.root.add_child(burst)
	await tree.process_frame
	var finished_count := [0]
	burst.finished.connect(func(_node): finished_count[0] += 1)
	burst.play(_preset({"duration": 0.03, "flash_duration": 0.02}), Vector2(120, 180), 1.0, false)
	assert_true(burst.visible)
	assert_eq(burst.position, Vector2(120, 180))
	assert_eq(burst.configured_particle_count, 40)
	assert_true(burst.get_node("Particles").emitting)
	assert_eq(burst.get_node("Visual/Icon").text, "★")
	await tree.create_timer(0.08).timeout
	assert_eq(finished_count[0], 1)
	assert_false(burst.active)
	assert_false(burst.visible)
	burst.queue_free()
	await tree.process_frame

func _test_reduced_motion_preserves_flash(tree: SceneTree) -> void:
	var burst = EffectBurstScene.instantiate()
	tree.root.add_child(burst)
	await tree.process_frame
	burst.play(_preset(), Vector2.ZERO, 0.25, true)
	assert_eq(burst.configured_particle_count, 10)
	assert_eq(burst.configured_shake_amplitude, 0.0)
	assert_eq(burst.configured_translation_amplitude, 0.0)
	assert_eq(burst.configured_flash_duration, 0.12)
	assert_true(burst.get_node("Visual/Icon").visible, "reduced motion removed the icon flash")
	burst.finish_now()
	burst.queue_free()
	await tree.process_frame

func _preset(overrides: Dictionary = {}) -> Dictionary:
	var preset := {
		"particle_count": 40,
		"duration": 0.2,
		"shake_amplitude": 8.0,
		"translation_amplitude": 18.0,
		"flash_duration": 0.12,
		"color": Color("ffd166"),
		"icon": "★",
		"label": "Great!",
	}
	for key in overrides:
		preset[key] = overrides[key]
	return preset
