class_name TactileButton
extends Control

const AssetCatalogScript = preload("res://src/presentation/assets/asset_catalog.gd")

signal press_started
signal accepted
signal cancelled
signal sfx_requested(id: StringName)

const NO_POINTER := -99
const MOUSE_POINTER := -1
const KEYBOARD_POINTER := -2

@export var reduced_motion := false
@export var haptics_enabled := true
@export var label_key := "button.continue"
@export var icon_name := "arrow_right"

@onready var _shadow: Panel = %Shadow
@onready var _visual: Control = %Visual
@onready var _surface: Panel = %Surface
@onready var _focus_ring: Panel = %FocusRing
@onready var _icon_label: Label = %IconLabel
@onready var _icon_texture: TextureRect = %IconTexture
@onready var _text_label: Label = %TextLabel

var _active_pointer := NO_POINTER
var _pointer_inside := false
var _enabled := true
var _restore_tween: Tween
var _normal_shadow_position := Vector2.ZERO
var _normal_shadow_modulate := Color.WHITE
var _haptic_driver: Callable
var _display_text_override := ""

func _ready() -> void:
	custom_minimum_size = custom_minimum_size.max(Vector2(48, 48))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_normal_shadow_position = _shadow.position
	_normal_shadow_modulate = _shadow.modulate
	_update_pivot()
	_apply_accessibility()
	resized.connect(_update_pivot)
	focus_entered.connect(_show_focus_ring)
	focus_exited.connect(_on_focus_exited)

func configure_accessibility(new_label_key: String, new_icon_name: String) -> void:
	label_key = new_label_key if not new_label_key.strip_edges().is_empty() else "button.continue"
	icon_name = new_icon_name
	if is_node_ready():
		_apply_accessibility()

func configure_display_text(display_text: String) -> void:
	_display_text_override = display_text.strip_edges()
	if is_node_ready():
		_apply_accessibility()

func set_haptic_driver(driver: Callable) -> void:
	_haptic_driver = driver

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	modulate.a = 1.0 if enabled else 0.55
	if not enabled and _active_pointer != NO_POINTER:
		_cancel_press()

func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press(MOUSE_POINTER, event.position)
		elif _active_pointer == MOUSE_POINTER:
			_finish_press(event.position)
		accept_event()
		return
	if event is InputEventMouseMotion and _active_pointer == MOUSE_POINTER:
		_update_pointer(event.position)
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed and _active_pointer == NO_POINTER:
			_begin_press(event.index, event.position)
		elif not event.pressed and _active_pointer == event.index:
			_finish_press(event.position)
		accept_event()
		return
	if event is InputEventScreenDrag and _active_pointer == event.index:
		_update_pointer(event.position)
		accept_event()
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed(&"ui_accept"):
		if _active_pointer == NO_POINTER:
			_begin_press(KEYBOARD_POINTER, size * 0.5)
		accept_event()
	elif event.is_action_released(&"ui_accept"):
		if _active_pointer == KEYBOARD_POINTER:
			_finish_press(size * 0.5)
		accept_event()

func _begin_press(pointer: int, local_position: Vector2) -> void:
	if _active_pointer != NO_POINTER or not _contains(local_position):
		return
	_active_pointer = pointer
	_pointer_inside = true
	_set_pressed_visual(true)
	_request_haptic(15)
	sfx_requested.emit(&"button_down")
	press_started.emit()

func _update_pointer(local_position: Vector2) -> void:
	var inside := _contains(local_position)
	if inside == _pointer_inside:
		return
	_pointer_inside = inside
	_set_pressed_visual(inside)

func _finish_press(local_position: Vector2) -> void:
	var was_inside := _contains(local_position)
	_active_pointer = NO_POINTER
	_pointer_inside = false
	_restore_visual()
	if was_inside:
		accepted.emit()
	else:
		cancelled.emit()

func _cancel_press() -> void:
	_active_pointer = NO_POINTER
	_pointer_inside = false
	_restore_visual()
	cancelled.emit()

func _contains(local_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(local_position)

func _set_pressed_visual(pressed: bool) -> void:
	_kill_restore_tween()
	if not pressed:
		_restore_visual()
		return
	if reduced_motion:
		_visual.scale = Vector2.ONE
		_visual.position = Vector2.ZERO
		_shadow.position = _normal_shadow_position
		_shadow.modulate = Color(0.72, 0.82, 0.86, 0.72)
		_surface.modulate = Color(0.92, 0.98, 1.0, 1.0)
		return
	_visual.scale = Vector2(0.96, 0.96)
	_visual.position = Vector2(0, 2)
	_shadow.position = Vector2(_normal_shadow_position.x, 2)
	_shadow.modulate = Color(1, 1, 1, 0.72)
	_surface.modulate = Color(0.95, 0.99, 1.0, 1.0)

func _restore_visual() -> void:
	_kill_restore_tween()
	if reduced_motion:
		_visual.scale = Vector2.ONE
		_visual.position = Vector2.ZERO
		_shadow.position = _normal_shadow_position
		_shadow.modulate = _normal_shadow_modulate
		_surface.modulate = Color.WHITE
		return
	_restore_tween = create_tween().set_parallel(true)
	_restore_tween.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_restore_tween.tween_property(_visual, "scale", Vector2.ONE, 0.18)
	_restore_tween.tween_property(_visual, "position", Vector2.ZERO, 0.18)
	_restore_tween.tween_property(_shadow, "position", _normal_shadow_position, 0.16)
	_restore_tween.tween_property(_shadow, "modulate", _normal_shadow_modulate, 0.12)
	_restore_tween.tween_property(_surface, "modulate", Color.WHITE, 0.12)

func _kill_restore_tween() -> void:
	if _restore_tween != null and _restore_tween.is_valid():
		_restore_tween.kill()
	_restore_tween = null

func _update_pivot() -> void:
	if is_node_ready():
		_visual.pivot_offset = size * 0.5

func _apply_accessibility() -> void:
	var visible_label := _display_text_override if not _display_text_override.is_empty() else tr(label_key)
	if visible_label.is_empty():
		visible_label = label_key
	_text_label.text = visible_label
	var release_icon := AssetCatalogScript.texture_for(StringName(icon_name))
	_icon_texture.texture = release_icon
	_icon_texture.visible = release_icon != null
	_icon_label.text = _icon_glyph(icon_name)
	_icon_label.visible = release_icon == null and not icon_name.is_empty()
	accessibility_name = visible_label
	accessibility_description = visible_label
	tooltip_text = visible_label

func _show_focus_ring() -> void:
	_focus_ring.visible = true

func _hide_focus_ring() -> void:
	_focus_ring.visible = false

func _on_focus_exited() -> void:
	_hide_focus_ring()
	if _active_pointer == KEYBOARD_POINTER:
		_cancel_press()

func _request_haptic(duration_ms: int) -> void:
	if not haptics_enabled:
		return
	if _haptic_driver.is_valid():
		_haptic_driver.call(duration_ms)
		return
	Input.vibrate_handheld(duration_ms)

func _icon_glyph(name: String) -> String:
	match name:
		"arrow_right":
			return "›"
		"check":
			return "✓"
		"star":
			return "★"
		"":
			return ""
	return "●"
