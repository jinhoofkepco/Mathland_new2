class_name AnswerInput
extends Control

signal answer_submitted(answer: Variant)
signal state_changed(answer: Variant)

var _interaction_enabled := true

func configure(_question: Dictionary) -> void:
	assert(false, "configure must be overridden")

func reset_state() -> void:
	assert(false, "reset_state must be overridden")

func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func is_interaction_enabled() -> bool:
	return _interaction_enabled

func get_answer_value() -> Variant:
	return null

func submit_current_answer() -> void:
	var answer: Variant = get_answer_value()
	if _interaction_enabled and answer != null:
		answer_submitted.emit(answer)
