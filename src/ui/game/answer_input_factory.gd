class_name AnswerInputFactory
extends RefCounted

const SCENES := {
	&"numeric_keypad": preload("res://src/ui/game/answer_inputs/numeric_keypad.tscn"),
	&"choice_grid": preload("res://src/ui/game/answer_inputs/choice_grid.tscn"),
	&"factor_slots": preload("res://src/ui/game/answer_inputs/factor_slots.tscn"),
}

static func supports(id: StringName) -> bool:
	return id == &"manipulative_submit" or SCENES.has(id)

static func create(id: StringName) -> Control:
	if not SCENES.has(id):
		return null
	return SCENES[id].instantiate()
