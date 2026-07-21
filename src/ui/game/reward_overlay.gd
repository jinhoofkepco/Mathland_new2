extends Control

signal dismissed

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")

var _kind := "reward"
var _amount := 0
var _effects_service: Variant
var _dismissed := false

func configure(params: Dictionary) -> void:
	var requested_kind := String(params.get("kind", "reward"))
	_kind = requested_kind if requested_kind in ["reward", "collection", "coupon"] else "reward"
	_amount = max(0, int(params.get("amount", 0)))
	_effects_service = params.get("effects_service")
	_dismissed = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.18, 0.2, 0.48)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 18
	center.offset_right = -18
	add_child(center)
	var card := MathlandUiScript.card("RewardCard", MathlandUiScript.SAND, 26)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(300, 0)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	var icon := MathlandUiScript.literal_label("★", 48, MathlandUiScript.CORAL)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(icon)
	var title := MathlandUiScript.label("reward.%s" % _kind, 25, MathlandUiScript.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	if _amount > 0:
		var amount := MathlandUiScript.literal_label("+%d" % _amount, 28, MathlandUiScript.DEEP_TEAL)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(amount)
	var skip := MathlandUiScript.tactile_button("SkipRewardButton", "reward.tap_to_continue", "arrow_right", Vector2(0, 56), 17)
	column.add_child(skip)
	MathlandUiScript.connect_tactile(skip, dismiss)
	if _effects_service != null and _effects_service.has_method("play"):
		_effects_service.play(StringName(_kind), size * 0.5)
	grab_focus.call_deferred()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dismiss()
		accept_event()
	elif event is InputEventScreenTouch and not event.pressed:
		dismiss()
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		dismiss()
		accept_event()

func preset_kind() -> String:
	return _kind

func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	dismissed.emit()
