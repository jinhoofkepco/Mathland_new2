extends "res://tests/support/test_case.gd"

const ManipulativeFactoryScript = preload("res://src/game/manipulatives/manipulative_factory.gd")
const AnswerInputFactoryScript = preload("res://src/ui/game/answer_input_factory.gd")

const VIEWPORT_SIZES := [Vector2i(360, 800), Vector2i(1080, 2400), Vector2i(800, 1280)]
const IDS := [&"counters", &"ten_frame", &"base_ten", &"number_line", &"answer_slots"]
const FIXTURES := {
	&"counters": {
		"config": {"capacity": 20},
		"question": {"resolved_parameters": {"initial_occupied": [0, 2, 4]}, "correct_answer": {"kind": "integer", "value": 3}},
	},
	&"ten_frame": {
		"config": {"frame_count": 2},
		"question": {"resolved_parameters": {"frame_count": 2, "occupied_cells": [0, 1, 2, 3]}, "correct_answer": {"kind": "integer", "value": 4}},
	},
	&"base_ten": {
		"config": {"max_place": "hundreds"},
		"question": {"resolved_parameters": {"place_counts": [1, 2, 3]}, "correct_answer": {"kind": "integer", "value": 123}},
	},
	&"number_line": {
		"config": {"axis_min": -10, "axis_max": 30},
		"question": {"resolved_parameters": {"axis_min": -10, "axis_max": 30, "start": 2, "visited_ticks": [2], "endpoint": 5}, "correct_answer": {"kind": "integer", "value": 5}},
	},
	&"answer_slots": {
		"config": {"slot_count": 6, "allowed_values": [2, 3, 5, 7]},
		"question": {"resolved_parameters": {"factors": [2, 2, 3]}, "correct_answer": {"kind": "integer_list", "values": [2, 2, 3], "order_matters": false}},
	},
}

func run(tree: SceneTree) -> void:
	await _test_manipulative_contract_at_portrait_sizes(tree)
	await _test_answer_input_contract(tree)

func _test_manipulative_contract_at_portrait_sizes(tree: SceneTree) -> void:
	assert_null(ManipulativeFactoryScript.create(&"unknown"))
	for viewport_size in VIEWPORT_SIZES:
		for id in IDS:
			var viewport := SubViewport.new()
			viewport.size = viewport_size
			tree.root.add_child(viewport)
			var node: Control = ManipulativeFactoryScript.create(id)
			assert_not_null(node, String(id))
			if node == null:
				viewport.queue_free()
				continue
			node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			viewport.add_child(node)
			var fixture: Dictionary = FIXTURES[id]
			node.configure(fixture.config, fixture.question)
			await tree.process_frame
			var saved: Dictionary = node.get_answer_state().duplicate(true)
			node.reset_state()
			node.apply_answer_state(saved)
			assert_eq(node.get_answer_state(), saved, "%s state round trip" % id)
			var malformed := saved.duplicate(true)
			malformed["unexpected"] = 1
			node.apply_answer_state(malformed)
			assert_eq(node.get_answer_state(), saved, "%s malformed state must be atomic" % id)
			node.set_interaction_enabled(false)
			assert_false(node.is_interaction_enabled())
			_assert_touch_targets(node, String(id))
			viewport.queue_free()
			await tree.process_frame

func _test_answer_input_contract(tree: SceneTree) -> void:
	assert_null(AnswerInputFactoryScript.create(&"unknown"))
	var fixtures := {
		&"numeric_keypad": {
			"question": {"correct_answer": {"kind": "integer", "value": 42}, "answer_layout": {"id": "numeric_keypad"}},
			"method": "set_integer", "argument": 42,
		},
		&"choice_grid": {
			"question": {"correct_answer": {"kind": "integer", "value": 7}, "answer_layout": {"id": "choice_grid", "options": {"values": [5, 7, 9]}}},
			"method": "select_option", "argument": 7,
		},
		&"factor_slots": {
			"question": {"correct_answer": {"kind": "integer_list", "values": [2, 2, 3], "order_matters": false}, "answer_layout": {"id": "factor_slots", "options": {"allowed_values": [2, 3, 5], "slot_count": 6}}},
			"method": "set_values", "argument": [2, 2, 3],
		},
	}
	for layout_id in fixtures:
		var input: Control = AnswerInputFactoryScript.create(layout_id)
		tree.root.add_child(input)
		var fixture: Dictionary = fixtures[layout_id]
		input.configure(fixture.question)
		await tree.process_frame
		var submitted: Array[Variant] = []
		input.answer_submitted.connect(func(answer: Variant): submitted.append(answer))
		input.call(fixture.method, fixture.argument)
		assert_eq(input.get_answer_value(), fixture.question.correct_answer)
		assert_eq(submitted, [], "editing cannot submit")
		input.submit_current_answer()
		assert_eq(submitted, [fixture.question.correct_answer])
		input.set_interaction_enabled(false)
		assert_false(input.is_interaction_enabled())
		input.submit_current_answer()
		assert_eq(submitted.size(), 1)
		_assert_touch_targets(input, String(layout_id))
		input.queue_free()
		await tree.process_frame

func _assert_touch_targets(root: Node, context: String) -> void:
	for candidate in root.find_children("*", "Control", true, false):
		if candidate.has_method("set_enabled"):
			assert_true(
				candidate.custom_minimum_size.x >= 48.0 and candidate.custom_minimum_size.y >= 48.0,
				"%s/%s is smaller than 48dp" % [context, candidate.name]
			)
