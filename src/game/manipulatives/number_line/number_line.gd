class_name NumberLineManipulative
extends "res://src/game/manipulatives/manipulative.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const MAX_TICKS := 128

var _axis_min := 0
var _axis_max := 10
var _initial_endpoint := 0
var _initial_visited: Array[int] = []
var _selected_endpoint := 0
var _visited_ticks: Array[int] = []
var _tick_buttons: Array[Control] = []
var _action_buttons: Array[Control] = []
var _grid: GridContainer
var _selection_label: Label

func _ready() -> void:
	_build_ui()
	_rebuild_ticks()
	_render()

func configure(config: Dictionary, question: Dictionary) -> void:
	var resolved := _resolved(question)
	var minimum: Variant = config.get("axis_min", resolved.get("axis_min", 0))
	var maximum: Variant = config.get("axis_max", resolved.get("axis_max", 10))
	if minimum is int and maximum is int and maximum >= minimum and maximum - minimum + 1 <= MAX_TICKS:
		_axis_min = minimum
		_axis_max = maximum
	else:
		_axis_min = 0
		_axis_max = 10
	var start: Variant = _initial_value(config, question, "selected_endpoint", resolved.get("start", _axis_min))
	_initial_endpoint = start if start is int and start >= _axis_min and start <= _axis_max else _axis_min
	var visited: Variant = _initial_value(config, question, "visited_ticks", resolved.get("visited_ticks", [_initial_endpoint]))
	_initial_visited = _validated_ticks(visited)
	if visited is Array and _initial_visited.size() != visited.size():
		_initial_visited = [_initial_endpoint]
	if _initial_endpoint not in _initial_visited:
		_initial_visited.append(_initial_endpoint)
		_initial_visited.sort()
	if is_node_ready():
		_rebuild_ticks()
	reset_state()

func reset_state() -> void:
	_selected_endpoint = _initial_endpoint
	_visited_ticks = _initial_visited.duplicate()
	_render()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _tick_buttons + _action_buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return {"selected_endpoint": _selected_endpoint, "visited_ticks": _visited_ticks.duplicate()}

func apply_answer_state(state: Dictionary) -> void:
	if state.size() != 2 or not state.get("selected_endpoint") is int or not state.get("visited_ticks") is Array:
		return
	var endpoint: int = state.selected_endpoint
	var visited := _validated_ticks(state.visited_ticks)
	if endpoint < _axis_min or endpoint > _axis_max or visited.size() != state.visited_ticks.size() or endpoint not in visited:
		return
	_selected_endpoint = endpoint
	_visited_ticks = visited
	_render()
	state_changed.emit(get_answer_state())

func select_tick(value: int) -> bool:
	if not is_interaction_enabled() or value < _axis_min or value > _axis_max:
		return false
	_selected_endpoint = value
	if value not in _visited_ticks:
		_visited_ticks.append(value)
		_visited_ticks.sort()
	_render()
	state_changed.emit(get_answer_state())
	return true

func submit_current_answer() -> void:
	if is_interaction_enabled():
		answer_submitted.emit({"kind": "integer", "value": _selected_endpoint})

func show_feedback(_correct: bool) -> void:
	pass

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_selection_label = MathlandUiScript.literal_label("0", 32, MathlandUiScript.DEEP_TEAL)
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_selection_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_action_buttons.append(submit)

func _rebuild_ticks() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.free()
	_tick_buttons.clear()
	for value in range(_axis_min, _axis_max + 1):
		var button := MathlandUiScript.tactile_button("Tick_%d" % value, "manipulative.number_line_tick", "", Vector2(48, 50), 15)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.accepted.connect(select_tick.bind(value))
		_grid.add_child(button)
		_tick_buttons.append(button)
	_render()

func _render() -> void:
	if _selection_label != null:
		_selection_label.text = "← %d →" % _selected_endpoint
	for index in _tick_buttons.size():
		var value := _axis_min + index
		var marker := "◆" if value == _selected_endpoint else ("•" if value in _visited_ticks else "|")
		_tick_buttons[index].configure_display_text("%s %d" % [marker, value])
		_tick_buttons[index].modulate = Color.WHITE if value in _visited_ticks else Color(0.84, 0.88, 0.9, 1.0)

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

func _validated_ticks(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for tick in value:
		if not tick is int or tick < _axis_min or tick > _axis_max or tick in result:
			return []
		result.append(tick)
	result.sort()
	return result
