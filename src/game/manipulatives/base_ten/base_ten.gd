class_name BaseTenManipulative
extends "res://src/game/manipulatives/manipulative.gd"

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const PLACES := ["hundreds", "tens", "ones"]

var _max_place := "hundreds"
var _initial := {"hundreds": 0, "tens": 0, "ones": 0}
var _counts := {"hundreds": 0, "tens": 0, "ones": 0}
var _labels: Dictionary = {}
var _buttons: Array[Control] = []
var _value_label: Label

func _ready() -> void:
	_build_ui()
	_render()

func configure(config: Dictionary, question: Dictionary) -> void:
	var requested: Variant = config.get("max_place", _resolved(question).get("max_place", "hundreds"))
	_max_place = requested if requested in PLACES else "hundreds"
	var values: Variant = _initial_value(config, question, "place_counts", _resolved(question).get("place_counts", [0, 0, 0]))
	var candidate := _counts_from_values(values)
	_initial = candidate if not candidate.is_empty() else {"hundreds": 0, "tens": 0, "ones": 0}
	reset_state()

func reset_state() -> void:
	_counts = _initial.duplicate(true)
	_render()
	state_changed.emit(get_answer_state())

func set_interaction_enabled(enabled: bool) -> void:
	super.set_interaction_enabled(enabled)
	for button in _buttons:
		if is_instance_valid(button):
			button.set_enabled(enabled)

func get_answer_state() -> Dictionary:
	return _counts.duplicate(true)

func apply_answer_state(state: Dictionary) -> void:
	if state.size() != 3:
		return
	var candidate := _counts_from_dictionary(state)
	if candidate.is_empty():
		return
	_counts = candidate
	_render()
	state_changed.emit(get_answer_state())

func change_place(place: String, delta: int) -> bool:
	if not is_interaction_enabled() or place not in PLACES or delta not in [-1, 1] or not _place_is_allowed(place):
		return false
	var next := int(_counts[place]) + delta
	if next < 0 or next > 9:
		return false
	_counts[place] = next
	_render()
	state_changed.emit(get_answer_state())
	return true

func submit_current_answer() -> void:
	if is_interaction_enabled():
		answer_submitted.emit({"kind": "integer", "value": _value()})

func show_feedback(_correct: bool) -> void:
	pass

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_value_label = MathlandUiScript.literal_label("0", 34, MathlandUiScript.DEEP_TEAL)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_value_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 7)
	column.add_child(grid)
	for place in PLACES:
		var label := MathlandUiScript.literal_label("", 20, MathlandUiScript.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(label)
		_labels[place] = label
	for place in PLACES:
		_add_button(grid, "Add_%s" % place, "manipulative.add", change_place.bind(place, 1))
	for place in PLACES:
		_add_button(grid, "Remove_%s" % place, "manipulative.remove", change_place.bind(place, -1))
	var submit := MathlandUiScript.tactile_button("SubmitButton", "manipulative.submit", "check", Vector2(0, 56), 18)
	submit.accepted.connect(submit_current_answer)
	column.add_child(submit)
	_buttons.append(submit)

func _add_button(parent: Container, node_name: String, key: String, callback: Callable) -> void:
	var button := MathlandUiScript.tactile_button(node_name, key, "", Vector2(48, 52), 16)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accepted.connect(callback)
	parent.add_child(button)
	_buttons.append(button)

func _render() -> void:
	if _value_label != null:
		_value_label.text = str(_value())
	var glyphs := {"hundreds": "▦", "tens": "▥", "ones": "●"}
	for place in PLACES:
		if _labels.has(place):
			_labels[place].text = "%s × %d" % [glyphs[place], _counts[place]]
	for button in _buttons:
		if button.name.begins_with("Add_") or button.name.begins_with("Remove_"):
			var place := String(button.name).get_slice("_", 1)
			button.visible = _place_is_allowed(place)

func _value() -> int:
	return int(_counts.hundreds) * 100 + int(_counts.tens) * 10 + int(_counts.ones)

func _place_is_allowed(place: String) -> bool:
	return PLACES.find(place) >= PLACES.find(_max_place)

func _counts_from_values(value: Variant) -> Dictionary:
	if value is Array and value.size() == 3:
		return _counts_from_dictionary({"hundreds": value[0], "tens": value[1], "ones": value[2]})
	if value is Dictionary:
		return _counts_from_dictionary(value)
	return {}

func _counts_from_dictionary(value: Dictionary) -> Dictionary:
	if value.size() != 3:
		return {}
	var result := {}
	for place in PLACES:
		var count: Variant = value.get(place)
		if not count is int or count < 0 or count > 9 or (count > 0 and not _place_is_allowed(place)):
			return {}
		result[place] = count
	return result

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
