class_name TenRodBoard
extends "res://src/game/manipulatives/manipulative.gd"

signal feedback_requested(kind: StringName, presentation: Dictionary)

const TactileButtonScene = preload("res://scenes/shared/tactile_button.tscn")
const MAX_VALUE := 99

var _maximum := MAX_VALUE
var _tens := 0
var _units := 0
var _interaction_enabled := true
var _prompt_label: Label
var _value_label: Label
var _tens_shapes: GridContainer
var _unit_shapes: GridContainer
var _tens_count_label: Label
var _unit_count_label: Label
var _buttons: Array[Control] = []

func _ready() -> void:
	_build_ui()
	_render_state()

func configure(config: Dictionary, question: Dictionary) -> void:
	var requested_max: Variant = config.get("maximum", MAX_VALUE)
	_maximum = int(requested_max) if requested_max is int and requested_max >= 0 and requested_max <= MAX_VALUE else MAX_VALUE
	if is_node_ready() and _prompt_label != null:
		var parameters: Variant = question.get("resolved_parameters", {})
		if parameters is Dictionary and parameters.get("left") is int and parameters.get("right") is int:
			_prompt_label.text = tr("activity.foundation_ten_rods.add_prompt") % [parameters.left, parameters.right]
		else:
			var prompt_key: Variant = question.get("prompt_key", "activity.foundation_ten_rods.add")
			_prompt_label.text = tr(prompt_key) if prompt_key is String and not prompt_key.is_empty() else tr("activity.foundation_ten_rods.add")
	reset_state()

func reset_state() -> void:
	_tens = 0
	_units = 0
	_render_state()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return {"tens": _tens, "units": _units, "value": _value()}

func apply_answer_state(state: Dictionary) -> void:
	if not _is_valid_state(state):
		return
	_tens = state.tens
	_units = state.units
	_render_state()
	state_changed.emit(get_answer_state())

func add_ten() -> bool:
	if not _interaction_enabled or _tens >= 9 or _value() + 10 > _maximum:
		return false
	_tens += 1
	_accept_mutation()
	return true

func remove_ten() -> bool:
	if not _interaction_enabled or _tens <= 0:
		return false
	_tens -= 1
	_accept_mutation()
	return true

func add_unit() -> bool:
	if not _interaction_enabled or _units >= 9 or _value() + 1 > _maximum:
		return false
	_units += 1
	_accept_mutation()
	return true

func remove_unit() -> bool:
	if not _interaction_enabled or _units <= 0:
		return false
	_units -= 1
	_accept_mutation()
	return true

func submit_current_answer() -> void:
	if _interaction_enabled:
		answer_submitted.emit(_value())

func show_feedback(correct: bool) -> void:
	feedback_requested.emit(
		&"correct" if correct else &"wrong",
		{
			"shape": "check" if correct else "retry",
			"text_key": "feedback.correct" if correct else "feedback.wrong",
		}
	)

func visual_shape_counts() -> Dictionary:
	return {
		"tens": _tens_shapes.get_child_count() if _tens_shapes != null else 0,
		"units": _unit_shapes.get_child_count() if _unit_shapes != null else 0,
	}

func visible_value_text() -> String:
	return _value_label.text if _value_label != null else ""

func visible_prompt_text() -> String:
	return _prompt_label.text if _prompt_label != null else ""

func visual_count_texts() -> Dictionary:
	return {
		"tens": _tens_count_label.text if _tens_count_label != null else "",
		"units": _unit_count_label.text if _unit_count_label != null else "",
	}

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("eaf8f4")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.text = tr("activity.foundation_ten_rods.add")
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.add_theme_color_override("font_color", Color("173f49"))
	column.add_child(_prompt_label)
	_value_label = Label.new()
	_value_label.name = "CurrentValueLabel"
	_value_label.custom_minimum_size = Vector2(0, 64)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_size_override("font_size", 42)
	_value_label.add_theme_color_override("font_color", Color("0d6974"))
	column.add_child(_value_label)
	var visual_card := PanelContainer.new()
	visual_card.name = "BaseTenVisualCard"
	visual_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visual_card.add_theme_stylebox_override("panel", _card_style(Color("fff7df"), 20))
	column.add_child(visual_card)
	var visual_row := HBoxContainer.new()
	visual_row.add_theme_constant_override("separation", 10)
	visual_card.add_child(visual_row)
	var tens_column := _shape_column("ten_rod", "manipulative.tens")
	_tens_shapes = tens_column.shapes
	_tens_count_label = tens_column.title
	visual_row.add_child(tens_column.root)
	var units_column := _shape_column("unit_cube", "manipulative.units")
	_unit_shapes = units_column.shapes
	_unit_count_label = units_column.title
	visual_row.add_child(units_column.root)
	var controls := GridContainer.new()
	controls.name = "ManipulativeControls"
	controls.columns = 2
	controls.add_theme_constant_override("h_separation", 8)
	controls.add_theme_constant_override("v_separation", 7)
	column.add_child(controls)
	_add_control_button(controls, "AddTenButton", "manipulative.add_ten", add_ten)
	_add_control_button(controls, "AddUnitButton", "manipulative.add_unit", add_unit)
	_add_control_button(controls, "RemoveTenButton", "manipulative.remove_ten", remove_ten)
	_add_control_button(controls, "RemoveUnitButton", "manipulative.remove_unit", remove_unit)
	var submit := _make_button("SubmitButton", "manipulative.submit", "ui.status.correct", Vector2(0, 58), 19)
	column.add_child(submit)
	submit.accepted.connect(submit_current_answer)
	_buttons.append(submit)

func _shape_column(node_name: String, label_key: String) -> Dictionary:
	var column := VBoxContainer.new()
	column.name = node_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = tr(label_key)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("365e67"))
	column.add_child(title)
	var shapes := GridContainer.new()
	shapes.name = "Shapes"
	shapes.columns = 5
	shapes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shapes.add_theme_constant_override("h_separation", 4)
	shapes.add_theme_constant_override("v_separation", 4)
	column.add_child(shapes)
	return {"root": column, "shapes": shapes, "title": title}

func _add_control_button(parent: GridContainer, node_name: String, label_key: String, callback: Callable) -> void:
	var button := _make_button(node_name, label_key, "", Vector2(0, 52), 15)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accepted.connect(callback)
	parent.add_child(button)
	_buttons.append(button)

func _make_button(node_name: String, label_key: String, icon_name: String, minimum: Vector2, font_size: int) -> Control:
	var button: Control = TactileButtonScene.instantiate()
	button.name = node_name
	button.custom_minimum_size = minimum.max(Vector2(48, 48))
	button.label_key = label_key
	button.icon_name = icon_name
	button.get_node("Visual/Content/TextLabel").add_theme_font_size_override("font_size", font_size)
	return button

func _accept_mutation() -> void:
	_render_state()
	state_changed.emit(get_answer_state())
	sfx_requested.emit(&"manipulative_place")

func _render_state() -> void:
	if not is_node_ready() or _value_label == null:
		return
	_value_label.text = str(_value())
	_tens_count_label.text = tr("manipulative.tens_count") % _tens
	_unit_count_label.text = tr("manipulative.units_count") % _units
	_clear_children(_tens_shapes)
	_clear_children(_unit_shapes)
	for index in _tens:
		var rod := Panel.new()
		rod.name = "TenRod_%d" % index
		rod.custom_minimum_size = Vector2(18, 54)
		rod.tooltip_text = tr("manipulative.ten_rod")
		rod.add_theme_stylebox_override("panel", _shape_style(Color("66d3b5"), 7))
		_tens_shapes.add_child(rod)
	for index in _units:
		var unit := Panel.new()
		unit.name = "Unit_%d" % index
		unit.custom_minimum_size = Vector2(22, 22)
		unit.tooltip_text = tr("manipulative.unit_cube")
		unit.add_theme_stylebox_override("panel", _shape_style(Color("76c8f0"), 6))
		_unit_shapes.add_child(unit)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()

func _value() -> int:
	return _tens * 10 + _units

func _is_valid_state(state: Dictionary) -> bool:
	if state.size() != 3 or not state.has("tens") or not state.has("units") or not state.has("value"):
		return false
	if not state.tens is int or not state.units is int or not state.value is int:
		return false
	return (
		state.tens >= 0
		and state.tens <= 9
		and state.units >= 0
		and state.units <= 9
		and state.value == state.tens * 10 + state.units
		and state.value <= _maximum
	)

func _card_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.09, 0.53, 0.58, 0.22)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	return style

func _shape_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("23415a")
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
