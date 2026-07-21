class_name Manipulative
extends Control

signal state_changed(state: Dictionary)
signal answer_submitted(answer: Variant)
signal sfx_requested(id: StringName)

func configure(_config: Dictionary, _question: Dictionary) -> void:
	assert(false, "configure must be overridden")

func reset_state() -> void:
	assert(false, "reset_state must be overridden")

func set_interaction_enabled(enabled: bool) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE

func get_answer_state() -> Dictionary:
	return {}

func apply_answer_state(_state: Dictionary) -> void:
	assert(false, "apply_answer_state must be overridden")
