class_name ManipulativeFactory
extends RefCounted

const SCENES := {
	&"counters": preload("res://src/game/manipulatives/counters/counters.tscn"),
	&"ten_frame": preload("res://src/game/manipulatives/ten_frame/ten_frame.tscn"),
	&"base_ten": preload("res://src/game/manipulatives/base_ten/base_ten.tscn"),
	&"number_line": preload("res://src/game/manipulatives/number_line/number_line.tscn"),
	&"answer_slots": preload("res://src/game/manipulatives/answer_slots/answer_slots.tscn"),
}

static func supports(id: StringName) -> bool:
	return id == &"none" or SCENES.has(id)

static func create(id: StringName) -> Control:
	if not SCENES.has(id):
		return null
	return SCENES[id].instantiate()
