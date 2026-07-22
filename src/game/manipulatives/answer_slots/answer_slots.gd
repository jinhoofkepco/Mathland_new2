class_name AnswerSlotsManipulative
extends "res://src/game/manipulatives/manipulative.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const MAX_SLOTS := 64

var _slot_count := 8
var _allowed_values: Array[int] = []
var _initial_tokens: Array[int] = []
var _tokens: Array[int] = []
var _order_matters := false
var _buttons: Array[Control] = []
var _token_label: Label
var _choice_grid: GridContainer

func _ready() -> void:
	_build_ui()
	_rebuild_choices()
	_render()

func configure(config: Dictionary, question: Dictionary) -> void:
	var resolved := _resolved(question)
	var requested_slots: Variant = config.get("slot_count", 8)
	_slot_count = requested_slots if requested_slots is int and requested_slots >= 1 and requested_slots <= MAX_SLOTS else 8
	var allowed: Variant = config.get("allowed_values", resolved.get("allowed_primes", []))
	_allowed_values = _validated_values(allowed, false)
	var answer: Variant = question.get("correct_answer", {})
	if _allowed_values.is_empty() and answer is Dictionary and answer.get("values") is Array:
		_allowed_values = _validated_values(answer.values, false)
		_allowed_values.sort()
		var unique: Array[int] = []
		for value in _allowed_values:
			if value not in unique:
				unique.append(value)
		_allowed_values = unique
	_order_matters = answer.get("order_matters", false) if answer is Dictionary and answer.get("order_matters") is bool else false
	var initial: Variant = _initial_value(config, question, "tokens", resolved.get("factors", []))
	_initial_tokens = _validated_values(initial, true)
	if initial is Array and _initial_tokens.size() != initial.size():
		_initial_tokens = []
	if is_node_ready():
		_rebuild_choices()
	reset_state()

func reset_state() -> void:
	_tokens = _initial_tokens.duplicate()
	_render()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return {"tokens": _tokens.duplicate()}

func apply_answer_state(state: Dictionary) -> void:
	if state.size() != 1 or not state.get("tokens") is Array:
		return
	var candidate := _validated_values(state.tokens, true)
	if candidate.size() != state.tokens.size():
		return
	_tokens = candidate
	_render()
	state_changed.emit(get_answer_state())

func add_token(value: int) -> bool:
	if not is_interaction_enabled() or _tokens.size() >= _slot_count or value not in _allowed_values:
		return false
	_tokens.append(value)
	_accept_change()
	return true

func remove_last_token() -> bool:
	if not is_interaction_enabled() or _tokens.is_empty():
		return false
	_tokens.pop_back()
	_accept_change()
	return true

func submit_current_answer() -> void:
	if is_interaction_enabled() and not _tokens.is_empty():
		answer_submitted.emit({"kind": "integer_list", "values": _tokens.duplicate(), "order_matters": _order_matters})

func show_feedback(_correct: bool) -> void:
	pass

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_token_label = MathlandUiScript.literal_label("_", 26, MathlandUiScript.DEEP_TEAL)
	_token_label.custom_minimum_size = Vector2(0, 58)
	_token_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_token_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_token_label)
	_choice_grid = GridContainer.new()
	_choice_grid.columns = 4
	_choice_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_grid.add_theme_constant_override("h_separation", 7)
	_choice_grid.add_theme_constant_override("v_separation", 7)
	column.add_child(_choice_grid)
	var remove := MathlandUiScript.tactile_button("RemoveTokenButton", "manipulative.remove", "", Vector2(0, 52), 16)
	remove.accepted.connect(remove_last_token)
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
		var button := MathlandUiScript.tactile_button("Token_%d" % value, "manipulative.token", "", Vector2(48, 52), 17)
		button.configure_display_text(str(value))
		button.accepted.connect(add_token.bind(value))
		_choice_grid.add_child(button)
		_buttons.append(button)

func _render() -> void:
	if _token_label != null:
		var parts := PackedStringArray()
		for value in _tokens:
			parts.append(str(value))
		_token_label.text = " × ".join(parts) if not parts.is_empty() else "_"

func _accept_change() -> void:
	_render()
	state_changed.emit(get_answer_state())

func _resolved(question: Dictionary) -> Dictionary:
	var value: Variant = question.get("resolved_parameters", {})
	return value if value is Dictionary else {}

func _initial_value(config: Dictionary, question: Dictionary, key: String, fallback: Variant) -> Variant:
	if config.has(key):
		return config[key]
	var manipulative: Variant = question.get("manipulative", {})
	if manipulative is Dictionary and manipulative.get("initial_state") is Dictionary and manipulative.initial_state.has(key):
		return manipulative.initial_state[key]
	return fallback

func _validated_values(value: Variant, enforce_allowed: bool) -> Array[int]:
	var result: Array[int] = []
	if not value is Array or value.size() > _slot_count:
		return result
	for item in value:
		if not item is int or (enforce_allowed and item not in _allowed_values):
			return []
		result.append(item)
	return result
