extends "res://tests/support/test_case.gd"

const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const ManipulativeFactoryScript = preload("res://src/game/manipulatives/manipulative_factory.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")
const IDS := [
	"foundations_counting", "foundations_number_bonds", "foundations_ten_frame",
	"foundations_base_ten", "foundations_number_line", "foundations_basic_operations",
]

func run(tree: SceneTree) -> void:
	for activity_id in IDS:
		var source := _load_source(activity_id)
		assert_false(source.is_empty(), activity_id)
		if source.is_empty():
			continue
		for band_value in source.difficulty_bands:
			var band: Dictionary = band_value
			var question: Dictionary = QuestionEngineScript.new().generate_question(source, StringName(band.band_id), 42)
			assert_false(question.is_empty(), "%s/%s" % [activity_id, band.band_id])
			if question.is_empty():
				continue
			var node: Control = ManipulativeFactoryScript.create(StringName(question.manipulative.id))
			assert_not_null(node)
			if node == null:
				continue
			tree.root.add_child(node)
			node.configure(question.manipulative.config, question)
			await tree.process_frame
			_apply_correct_state(node, question)
			var submitted: Array[Variant] = []
			node.answer_submitted.connect(func(answer: Variant): submitted.append(answer))
			node.submit_current_answer()
			assert_eq(submitted, [question.correct_answer], "%s/%s" % [activity_id, band.band_id])
			node.queue_free()
			await tree.process_frame

func _load_source(activity_id: String) -> Dictionary:
	var path := "res://content/sources/%s.json" % activity_id
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = ContentValidatorScript.new().parse_json(FileAccess.get_file_as_string(path), path)
	return parsed.value if parsed.ok and parsed.value is Dictionary else {}

func _apply_correct_state(node: Control, question: Dictionary) -> void:
	var value := int(question.correct_answer.value)
	match String(question.manipulative.id):
		"counters":
			node.apply_answer_state({"occupied": _indices(value)})
		"ten_frame":
			node.apply_answer_state({"occupied_cells": _indices(value), "frame_count": int(question.resolved_parameters.frame_count)})
		"base_ten":
			node.apply_answer_state({
				"hundreds": int(floor(value / 100.0)),
				"tens": int(floor(value / 10.0)) % 10,
				"ones": value % 10,
			})
		"number_line":
			var visited: Array = question.resolved_parameters.visited_ticks.duplicate()
			if value not in visited:
				visited.append(value)
			visited.sort()
			node.apply_answer_state({"selected_endpoint": value, "visited_ticks": visited})

func _indices(count: int) -> Array[int]:
	var result: Array[int] = []
	for index in count:
		result.append(index)
	return result
