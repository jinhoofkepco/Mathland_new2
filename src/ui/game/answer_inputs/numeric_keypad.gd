class_name NumericKeypad
extends "res://src/ui/game/answer_inputs/answer_input.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_DIGITS := 16

var _entry := ""
var _buttons: Array[Control] = []
var _display: Label

func _ready() -> void:
	_build_ui()
	_render()

func configure(_question: Dictionary) -> void:
	reset_state()

func reset_state() -> void:
	_entry = ""
	_render()
	state_changed.emit(get_answer_value())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_value() -> Variant:
	if _entry.is_empty() or _entry == "-":
		return null
	if not _entry.is_valid_int():
		return null
	var value := _entry.to_int()
	if value < -MAX_SAFE_INTEGER or value > MAX_SAFE_INTEGER:
		return null
	return {"kind": "integer", "value": value}

func set_integer(value: int) -> bool:
	if not is_interaction_enabled() or value < -MAX_SAFE_INTEGER or value > MAX_SAFE_INTEGER:
		return false
	_entry = str(value)
	_accept_change()
	return true

func press_digit(digit: int) -> bool:
	if not is_interaction_enabled() or digit < 0 or digit > 9:
		return false
	var digits := _entry.trim_prefix("-")
	if digits.length() >= MAX_DIGITS:
		return false
	if digits == "0":
		digits = str(digit)
	else:
		digits += str(digit)
	_entry = ("-" if _entry.begins_with("-") else "") + digits
	if get_answer_value() == null:
		_entry = _entry.left(-1)
		return false
	_accept_change()
	return true

func toggle_negative() -> bool:
	if not is_interaction_enabled():
		return false
	_entry = _entry.trim_prefix("-") if _entry.begins_with("-") else "-" + _entry
	_accept_change()
	return true

func erase_last() -> bool:
	if not is_interaction_enabled() or _entry.is_empty():
		return false
	_entry = _entry.left(-1)
	_accept_change()
	return true

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	_display = MathlandUiScript.literal_label("_", 32, MathlandUiScript.DEEP_TEAL)
	_display.name = "AnswerDisplay"
	_display.custom_minimum_size = Vector2(0, 54)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_display)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	column.add_child(grid)
	for digit in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
		_add_button(grid, "Digit_%d" % digit, str(digit), press_digit.bind(digit))
	_add_button(grid, "NegativeButton", "−", toggle_negative)
	_add_button(grid, "Digit_0", "0", press_digit.bind(0))
	_add_button(grid, "EraseButton", "⌫", erase_last)
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_buttons.append(submit)

func _add_button(parent: Container, node_name: String, text: String, callback: Callable) -> void:
	var button := MathlandUiScript.tactile_button(node_name, "answer.key", "", Vector2(48, 50), 17)
	button.configure_display_text(text)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accepted.connect(callback)
	parent.add_child(button)
	_buttons.append(button)

func _accept_change() -> void:
	_render()
	state_changed.emit(get_answer_value())

func _render() -> void:
	if _display != null:
		_display.text = _entry if not _entry.is_empty() else "_"
