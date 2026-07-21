extends "res://tests/support/test_case.gd"

const TenRodBoardScene = preload("res://scenes/game/manipulatives/ten_rod_board.tscn")

func run(tree: SceneTree) -> void:
	await _test_state_visuals_submission_and_interaction_lock(tree)
	await _test_bounds_reset_and_invalid_state_are_contained(tree)

func _test_state_visuals_submission_and_interaction_lock(tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	tree.root.add_child(viewport)
	var board: Control = TenRodBoardScene.instantiate()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(board)
	board.configure({"maximum": 99}, {
		"correct_answer": 7,
		"prompt_key": "activity.foundation_ten_rods.add",
		"resolved_parameters": {"left": 3, "right": 4},
	})
	await tree.process_frame
	var changes: Array[Dictionary] = []
	var submitted: Array[Variant] = []
	var sfx: Array[StringName] = []
	board.state_changed.connect(func(state: Dictionary): changes.append(state.duplicate(true)))
	board.answer_submitted.connect(func(answer: Variant): submitted.append(answer))
	assert_true(board.has_signal("sfx_requested"), "manipulative audio boundary is missing")
	if board.has_signal("sfx_requested"):
		board.sfx_requested.connect(func(id: StringName): sfx.append(id))
	assert_true(board.add_ten())
	assert_true(board.add_unit())
	assert_true(board.add_unit())
	assert_true(board.add_unit())
	assert_eq(board.get_answer_state(), {"tens": 1, "units": 3, "value": 13})
	assert_eq(board.visual_shape_counts(), {"tens": 1, "units": 3})
	assert_eq(board.visual_count_texts(), {"tens": "10막대 × 1", "units": "낱개 × 3"})
	assert_eq(changes.back(), {"tens": 1, "units": 3, "value": 13})
	assert_eq(sfx, [&"manipulative_place", &"manipulative_place", &"manipulative_place", &"manipulative_place"])
	board.reset_state()
	assert_eq(board.get_answer_state(), {"tens": 0, "units": 0, "value": 0})
	board.apply_answer_state({"tens": 0, "units": 7, "value": 7})
	assert_eq(board.get_answer_state(), {"tens": 0, "units": 7, "value": 7})
	assert_eq(board.visual_shape_counts(), {"tens": 0, "units": 7})
	assert_eq(board.visual_count_texts(), {"tens": "10막대 × 0", "units": "낱개 × 7"})
	assert_eq(board.visible_value_text(), "7")
	assert_eq(board.visible_prompt_text(), "3 + 4 = ?")
	board.set_interaction_enabled(false)
	assert_false(board.add_unit())
	assert_false(board.remove_unit())
	assert_eq(board.get_answer_state().value, 7)
	board.submit_current_answer()
	assert_eq(submitted, [], "disabled interaction must also block submit")
	board.set_interaction_enabled(true)
	board.submit_current_answer()
	assert_eq(submitted, [7])
	var feedback: Array[Dictionary] = []
	board.feedback_requested.connect(func(kind: StringName, presentation: Dictionary):
		feedback.append({"kind": kind, "presentation": presentation.duplicate(true)})
	)
	board.show_feedback(true)
	assert_eq(feedback.back(), {
		"kind": &"correct",
		"presentation": {"shape": "check", "text_key": "feedback.correct"},
	})
	for action_name in ["AddTenButton", "RemoveTenButton", "AddUnitButton", "RemoveUnitButton", "SubmitButton"]:
		var action: Control = board.find_child(action_name, true, false)
		assert_not_null(action)
		if action != null:
			assert_true(action.size.x >= 48.0 and action.size.y >= 48.0)
	viewport.queue_free()
	await tree.process_frame

func _test_bounds_reset_and_invalid_state_are_contained(tree: SceneTree) -> void:
	var board: Control = TenRodBoardScene.instantiate()
	tree.root.add_child(board)
	board.configure({}, {"correct_answer": 9, "prompt_key": "activity.foundation_ten_rods.add"})
	await tree.process_frame
	for index in 9:
		assert_true(board.add_ten())
	for index in 9:
		assert_true(board.add_unit())
	assert_eq(board.get_answer_state().value, 99)
	assert_false(board.add_ten())
	assert_false(board.add_unit())
	var before: Dictionary = board.get_answer_state()
	for invalid in [
		{"tens": 10, "units": 0, "value": 100},
		{"tens": 0, "units": 8, "value": 7},
		{"tens": -1, "units": 0, "value": -10},
		{"tens": 0, "units": 1},
	]:
		board.apply_answer_state(invalid)
		assert_eq(board.get_answer_state(), before)
	for index in 9:
		assert_true(board.remove_ten())
	for index in 9:
		assert_true(board.remove_unit())
	assert_eq(board.get_answer_state().value, 0)
	assert_false(board.remove_ten())
	assert_false(board.remove_unit())
	board.queue_free()
	await tree.process_frame
