extends "res://tests/support/test_case.gd"

const ManipulativeFactoryScript = preload("res://src/game/manipulatives/manipulative_factory.gd")

func run(tree: SceneTree) -> void:
	await _test_explicit_typed_submission_and_atomic_state(tree)

func _test_explicit_typed_submission_and_atomic_state(tree: SceneTree) -> void:
	var cases := [
		{
			"id": &"counters", "config": {"capacity": 10},
			"question": {"resolved_parameters": {"initial_occupied": [0, 1]}, "correct_answer": {"kind": "integer", "value": 3}},
			"mutation": [&"toggle_item", 2], "expected": {"occupied": [0, 1, 2]},
			"answer": {"kind": "integer", "value": 3},
		},
		{
			"id": &"ten_frame", "config": {"frame_count": 1},
			"question": {"resolved_parameters": {"frame_count": 1, "occupied_cells": [0, 1]}, "correct_answer": {"kind": "integer", "value": 3}},
			"mutation": [&"toggle_cell", 2], "expected": {"occupied_cells": [0, 1, 2], "frame_count": 1},
			"answer": {"kind": "integer", "value": 3},
		},
		{
			"id": &"base_ten", "config": {"max_place": "hundreds"},
			"question": {"resolved_parameters": {"place_counts": [1, 2, 3]}, "correct_answer": {"kind": "integer", "value": 124}},
			"mutation": [&"change_place", "ones", 1], "expected": {"hundreds": 1, "tens": 2, "ones": 4},
			"answer": {"kind": "integer", "value": 124},
		},
		{
			"id": &"number_line", "config": {"axis_min": 0, "axis_max": 10},
			"question": {"resolved_parameters": {"axis_min": 0, "axis_max": 10, "start": 2, "visited_ticks": [2], "endpoint": 5}, "correct_answer": {"kind": "integer", "value": 5}},
			"mutation": [&"select_tick", 5], "expected": {"selected_endpoint": 5, "visited_ticks": [2, 5]},
			"answer": {"kind": "integer", "value": 5},
		},
		{
			"id": &"answer_slots", "config": {"slot_count": 5, "allowed_values": [2, 3, 5]},
			"question": {"resolved_parameters": {"factors": [2, 2]}, "correct_answer": {"kind": "integer_list", "values": [2, 2, 3], "order_matters": false}},
			"mutation": [&"add_token", 3], "expected": {"tokens": [2, 2, 3]},
			"answer": {"kind": "integer_list", "values": [2, 2, 3], "order_matters": false},
		},
	]
	for case_value in cases:
		var case: Dictionary = case_value
		var node: Control = ManipulativeFactoryScript.create(case.id)
		tree.root.add_child(node)
		node.configure(case.config, case.question)
		await tree.process_frame
		var submitted: Array[Variant] = []
		node.answer_submitted.connect(func(answer: Variant): submitted.append(answer))
		var arguments: Array = case.mutation.slice(1)
		assert_true(bool(node.callv(case.mutation[0], arguments)))
		assert_eq(node.get_answer_state(), case.expected)
		assert_eq(submitted, [], "intermediate mutation submitted an answer")
		var before: Dictionary = node.get_answer_state().duplicate(true)
		node.apply_answer_state({"bad": 1})
		assert_eq(node.get_answer_state(), before)
		node.submit_current_answer()
		assert_eq(submitted, [case.answer])
		node.queue_free()
		await tree.process_frame
