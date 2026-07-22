extends "res://tests/support/test_case.gd"

const AnswerInputFactoryScript = preload("res://src/ui/game/answer_input_factory.gd")

func run(tree: SceneTree) -> void:
	var input: Control = AnswerInputFactoryScript.create(&"choice_grid")
	tree.root.add_child(input)
	input.configure({
		"correct_answer": {"kind": "integer", "value": 7},
		"answer_layout": {"id": "choice_grid", "options": {"values": [5, 7, 9]}},
	})
	await tree.process_frame
	var selected: Control = input.find_child("Choice_7", true, false)
	var other: Control = input.find_child("Choice_5", true, false)
	assert_not_null(selected)
	assert_not_null(other)
	if selected == null or other == null:
		input.queue_free()
		await tree.process_frame
		return
	var before_text := _visible_text(selected)
	var before_description := String(selected.accessibility_description)
	assert_true(input.select_option(7))
	var selected_text := _visible_text(selected)
	var other_text := _visible_text(other)
	assert_ne(selected_text, before_text, "selection must have a persistent non-colour indicator")
	assert_true(selected_text.begins_with("✓"), "selected choice is missing its visible marker")
	assert_true(other_text.begins_with("○"), "unselected choice is missing its visible marker")
	assert_ne(String(selected.accessibility_description), before_description, "accessibility state did not announce selection")
	assert_true(String(selected.accessibility_description).contains("7"))
	other.grab_focus()
	assert_true(_visible_text(selected).begins_with("✓"), "selection marker disappeared after focus moved")
	input.queue_free()
	await tree.process_frame


func _visible_text(button: Control) -> String:
	var label: Label = button.get_node("Visual/Content/TextLabel")
	return label.text
