class_name FactorSlots
extends "res://src/ui/game/answer_inputs/answer_input.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const MAX_SLOTS := 64

var _allowed_values: Array[int] = []
var _slot_count := 8
var _values: Array[int] = []
var _order_matters := false
var _buttons: Array[Control] = []
var _choice_grid: GridContainer
var _display: Label

func _ready() -> void:
	_build_ui()

func configure(question: Dictionary) -> void:
	var answer: Variant = question.get("correct_answer", {})
	_order_matters = answer.get("order_matters", false) if answer is Dictionary and answer.get("order_matters") is bool else false
	var layout: Variant = question.get("answer_layout", {})
	var options: Variant = layout.get("options", {}) if layout is Dictionary else {}
	var resolved: Variant = question.get("resolved_parameters", {})
	var allowed: Variant = options.get("allowed_values", []) if options is Dictionary else []
	if allowed is Array and allowed.is_empty() and resolved is Dictionary:
		allowed = resolved.get("allowed_primes", [])
	if allowed is Array and allowed.is_empty() and answer is Dictionary:
		allowed = answer.get("values", [])
	_allowed_values = _valid_values(allowed, false)
	var unique: Array[int] = []
	for value in _allowed_values:
		if value not in unique:
			unique.append(value)
	_allowed_values = unique
	var requested_slots: Variant = options.get("slot_count", 8) if options is Dictionary else 8
	_slot_count = requested_slots if requested_slots is int and requested_slots >= 1 and requested_slots <= MAX_SLOTS else 8
	_rebuild_choices()
	reset_state()

func reset_state() -> void:
	_values.clear()
	_render()
	state_changed.emit(null)

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_value() -> Variant:
	if _values.is_empty():
		return null
	return {"kind": "integer_list", "values": _values.duplicate(), "order_matters": _order_matters}

func set_values(values: Array) -> bool:
	if not is_interaction_enabled():
		return false
	var candidate := _valid_values(values, true)
	if candidate.size() != values.size():
		return false
	_values = candidate
	_accept_change()
	return true

func add_value(value: int) -> bool:
	if not is_interaction_enabled() or _values.size() >= _slot_count or value not in _allowed_values:
		return false
	_values.append(value)
	_accept_change()
	return true

func remove_last() -> bool:
	if not is_interaction_enabled() or _values.is_empty():
		return false
	_values.pop_back()
	_accept_change()
	return true

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 7)
	add_child(column)
	_display = MathlandUiScript.literal_label("_", 25, MathlandUiScript.DEEP_TEAL)
	_display.custom_minimum_size = Vector2(0, 54)
	_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_display)
	_choice_grid = GridContainer.new()
	_choice_grid.columns = 4
	_choice_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_grid.add_theme_constant_override("h_separation", 7)
	_choice_grid.add_theme_constant_override("v_separation", 7)
	column.add_child(_choice_grid)
	var remove := MathlandUiScript.tactile_button("RemoveFactorButton", "manipulative.remove", "", Vector2(0, 52), 16)
	remove.accepted.connect(remove_last)
	column.add_child(remove)
	_buttons.append(remove)
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_buttons.append(submit)

func _rebuild_choices() -> void:
	if _choice_grid == null:
		return
	for child in _choice_grid.get_children():
		_buttons.erase(child)
		child.free()
	for value in _allowed_values:
		var button := MathlandUiScript.tactile_button("Factor_%d" % value, "answer.factor", "", Vector2(48, 52), 17)
		button.configure_display_text(str(value))
		button.accepted.connect(add_value.bind(value))
		_choice_grid.add_child(button)
		_buttons.append(button)

func _accept_change() -> void:
	_render()
	state_changed.emit(get_answer_value())

func _render() -> void:
	if _display != null:
		var parts := PackedStringArray()
		for value in _values:
			parts.append(str(value))
		_display.text = " × ".join(parts) if not parts.is_empty() else "_"

func _valid_values(value: Variant, enforce_allowed: bool) -> Array[int]:
	var result: Array[int] = []
	if not value is Array or value.size() > _slot_count:
		return result
	for item in value:
		if not item is int or (enforce_allowed and item not in _allowed_values):
			return []
		result.append(item)
	return result
