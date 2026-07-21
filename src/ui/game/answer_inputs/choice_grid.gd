class_name ChoiceGrid
extends "res://src/ui/game/answer_inputs/answer_input.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")

var _options: Array[int] = []
var _selected: Variant = null
var _buttons: Array[Control] = []
var _grid: GridContainer

func _ready() -> void:
	_build_ui()

func configure(question: Dictionary) -> void:
	var layout: Variant = question.get("answer_layout", {})
	var options_value: Variant = layout.get("options", {}) if layout is Dictionary else {}
	var values: Variant = options_value.get("values", []) if options_value is Dictionary else []
	_options = _valid_options(values)
	if _options.is_empty():
		var answer: Variant = question.get("correct_answer", {})
		if answer is Dictionary and answer.get("kind") == "integer" and answer.get("value") is int:
			_options = [int(answer.value)]
	_rebuild_options()
	reset_state()

func reset_state() -> void:
	_selected = null
	_render()
	state_changed.emit(null)

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_value() -> Variant:
	return {"kind": "integer", "value": int(_selected)} if _selected is int else null

func select_option(value: int) -> bool:
	if not is_interaction_enabled() or value not in _options:
		return false
	_selected = value
	_render()
	state_changed.emit(get_answer_value())
	return true

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_grid)
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_buttons.append(submit)

func _rebuild_options() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		_buttons.erase(child)
		child.free()
	for value in _options:
		var button := MathlandUiScript.tactile_button("Choice_%d" % value, "answer.choice", "", Vector2(48, 56), 18)
		button.configure_display_text(str(value))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.accepted.connect(select_option.bind(value))
		_grid.add_child(button)
		_buttons.append(button)

func _render() -> void:
	for button in _buttons:
		if String(button.name).begins_with("Choice_"):
			var value := String(button.name).trim_prefix("Choice_").to_int()
			button.modulate = Color.WHITE if value == _selected else Color(0.84, 0.88, 0.9, 1.0)

func _valid_options(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array or value.is_empty() or value.size() > 12:
		return result
	for option in value:
		if not option is int or option in result:
			return []
		result.append(option)
	return result
