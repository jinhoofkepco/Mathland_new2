extends "res://tests/support/test_case.gd"

const LearningEventV1 = preload("res://src/events/learning_event_v1.gd")

func run(_tree: SceneTree) -> void:
	var file := FileAccess.open("res://tests/fixtures/contracts/learning_event_v1.json", FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	assert_true(LearningEventV1.validate(parsed).is_empty())
	var unknown: Dictionary = parsed.duplicate(true)
	unknown.injected = true
	assert_false(LearningEventV1.validate(unknown).is_empty())
	var missing_answer: Dictionary = parsed.duplicate(true)
	missing_answer.erase("submitted_answer")
	assert_false(LearningEventV1.validate(missing_answer).is_empty())
	var invalid_type: Dictionary = parsed.duplicate(true)
	invalid_type.event_type = "invented"
	assert_false(LearningEventV1.validate(invalid_type).is_empty())
	var invalid_uuid: Dictionary = parsed.duplicate(true)
	invalid_uuid.event_id = "not-a-uuid"
	assert_false(LearningEventV1.validate(invalid_uuid).is_empty())
	var invalid_sequence: Dictionary = parsed.duplicate(true)
	invalid_sequence.sequence = 0
	assert_false(LearningEventV1.validate(invalid_sequence).is_empty())
