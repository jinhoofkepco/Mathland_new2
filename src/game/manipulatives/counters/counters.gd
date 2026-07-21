class_name CountersManipulative
extends "res://src/game/manipulatives/manipulative.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const MAX_CAPACITY := 128

var _capacity := 20
var _initial_occupied: Array[int] = []
var _occupied: Array[int] = []
var _item_buttons: Array[Control] = []
var _action_buttons: Array[Control] = []
var _grid: GridContainer
var _count_label: Label

func _ready() -> void:
	_build_ui()
	_rebuild_items()
	_render()

func configure(config: Dictionary, question: Dictionary) -> void:
	var requested: Variant = config.get("capacity", _resolved(question).get("item_ids", []).size())
	if requested is int and requested >= 1 and requested <= MAX_CAPACITY:
		_capacity = requested
	else:
		_capacity = 20
	var initial: Variant = _initial_value(config, question, "initial_occupied", [])
	_initial_occupied = _validated_indices(initial, _capacity)
	if initial is Array and _initial_occupied.size() != initial.size():
		_initial_occupied = []
	if is_node_ready():
		_rebuild_items()
	reset_state()

func reset_state() -> void:
	_occupied = _initial_occupied.duplicate()
	_render()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _item_buttons + _action_buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return {"occupied": _occupied.duplicate()}

func apply_answer_state(state: Dictionary) -> void:
	if state.size() != 1 or not state.has("occupied") or not state.occupied is Array:
		return
	var candidate := _validated_indices(state.occupied, _capacity)
	if candidate.size() != state.occupied.size():
		return
	_occupied = candidate
	_render()
	state_changed.emit(get_answer_state())

func toggle_item(index: int) -> bool:
	if not is_interaction_enabled() or index < 0 or index >= _capacity:
		return false
	var position := _occupied.find(index)
	if position >= 0:
		_occupied.remove_at(position)
	else:
		_occupied.append(index)
		_occupied.sort()
	_accept_change()
	return true

func submit_current_answer() -> void:
	if is_interaction_enabled():
		answer_submitted.emit({"kind": "integer", "value": _occupied.size()})

func show_feedback(_correct: bool) -> void:
	pass

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_count_label = MathlandUiScript.literal_label("0", 28, MathlandUiScript.DEEP_TEAL)
	_count_label.name = "CounterCountLabel"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count_label)
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

func _rebuild_items() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.free()
	_item_buttons.clear()
	for index in _capacity:
		var button := MathlandUiScript.tactile_button("Counter_%d" % index, "manipulative.counter", "", Vector2(48, 48), 14)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.accepted.connect(toggle_item.bind(index))
		_grid.add_child(button)
		_item_buttons.append(button)
	_render()

func _render() -> void:
	if _count_label != null:
		_count_label.text = str(_occupied.size())
	for index in _item_buttons.size():
		var occupied := index in _occupied
		_item_buttons[index].configure_display_text(("● " if occupied else "○ ") + str(index + 1))
		_item_buttons[index].modulate = Color.WHITE if occupied else Color(0.82, 0.86, 0.88, 1.0)

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
	return _resolved(question).get(key, fallback)

func _validated_indices(value: Variant, upper: int) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for item in value:
		if not item is int or item < 0 or item >= upper or item in result:
			return []
		result.append(item)
	result.sort()
	return result
