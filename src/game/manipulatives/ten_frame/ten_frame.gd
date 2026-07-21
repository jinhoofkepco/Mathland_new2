class_name TenFrameManipulative
extends "res://src/game/manipulatives/manipulative.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")

var _frame_count := 1
var _initial_cells: Array[int] = []
var _occupied_cells: Array[int] = []
var _cell_buttons: Array[Control] = []
var _action_buttons: Array[Control] = []
var _grid: GridContainer
var _count_label: Label

func _ready() -> void:
	_build_ui()
	_rebuild_cells()
	_render()

func configure(config: Dictionary, question: Dictionary) -> void:
	var resolved := _resolved(question)
	var requested: Variant = config.get("frame_count", resolved.get("frame_count", 1))
	_frame_count = requested if requested in [1, 2] else 1
	var initial: Variant = _initial_value(config, question, "occupied_cells", [])
	_initial_cells = _validated_indices(initial)
	if initial is Array and _initial_cells.size() != initial.size():
		_initial_cells = []
	if is_node_ready():
		_rebuild_cells()
	reset_state()

func reset_state() -> void:
	_occupied_cells = _initial_cells.duplicate()
	_render()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _cell_buttons + _action_buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return {"occupied_cells": _occupied_cells.duplicate(), "frame_count": _frame_count}

func apply_answer_state(state: Dictionary) -> void:
	if state.size() != 2 or state.get("frame_count") != _frame_count or not state.get("occupied_cells") is Array:
		return
	var candidate := _validated_indices(state.occupied_cells)
	if candidate.size() != state.occupied_cells.size():
		return
	_occupied_cells = candidate
	_render()
	state_changed.emit(get_answer_state())

func toggle_cell(index: int) -> bool:
	if not is_interaction_enabled() or index < 0 or index >= _frame_count * 10:
		return false
	var position := _occupied_cells.find(index)
	if position >= 0:
		_occupied_cells.remove_at(position)
	else:
		_occupied_cells.append(index)
		_occupied_cells.sort()
	_render()
	state_changed.emit(get_answer_state())
	return true

func submit_current_answer() -> void:
	if is_interaction_enabled():
		answer_submitted.emit({"kind": "integer", "value": _occupied_cells.size()})

func show_feedback(_correct: bool) -> void:
	pass

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_count_label = MathlandUiScript.literal_label("0", 28, MathlandUiScript.DEEP_TEAL)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count_label)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 7)
	_grid.add_theme_constant_override("v_separation", 7)
	center.add_child(_grid)
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_action_buttons.append(submit)

func _rebuild_cells() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.free()
	_cell_buttons.clear()
	for index in _frame_count * 10:
		var button := MathlandUiScript.tactile_button("Cell_%d" % index, "manipulative.ten_frame_cell", "", Vector2(52, 52), 18)
		button.accepted.connect(toggle_cell.bind(index))
		_grid.add_child(button)
		_cell_buttons.append(button)
	_render()

func _render() -> void:
	if _count_label != null:
		_count_label.text = str(_occupied_cells.size())
	for index in _cell_buttons.size():
		var occupied := index in _occupied_cells
		_cell_buttons[index].configure_display_text("●" if occupied else "○")
		_cell_buttons[index].modulate = Color.WHITE if occupied else Color(0.82, 0.86, 0.88, 1.0)

func _resolved(question: Dictionary) -> Dictionary:
	var value: Variant = question.get("resolved_parameters", {})
	return value if value is Dictionary else {}

func _initial_value(config: Dictionary, question: Dictionary, key: String, fallback: Variant) -> Variant:
	if config.has(key):
		return config[key]
	var manipulative: Variant = question.get("manipulative", {})
	if manipulative is Dictionary and manipulative.get("initial_state") is Dictionary and manipulative.initial_state.has(key):
		return manipulative.initial_state[key]
	return _resolved(question).get(key, fallback)

func _validated_indices(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for item in value:
		if not item is int or item < 0 or item >= _frame_count * 10 or item in result:
			return []
		result.append(item)
	result.sort()
	return result
