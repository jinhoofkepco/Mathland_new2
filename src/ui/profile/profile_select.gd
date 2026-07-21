extends "res://src/ui/shared/child_screen.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const ProfileCreateDialogScene = preload("res://scenes/profile/profile_create_dialog.tscn")

var _profile_buttons: VBoxContainer
var _pin_input: LineEdit
var _unlock_button: Control
var _error_label: Label
var _dialog: Control
var _selected_id := ""

func _ready() -> void:
	var ui := MathlandUiScript.scaffold(self, "profile.select.title", "profile.select.subtitle")
	var body: VBoxContainer = ui.body
	var hero := MathlandUiScript.card("MoaWelcomeCard", MathlandUiScript.MINT, 22)
	hero.custom_minimum_size = Vector2(0, 86)
	body.add_child(hero)
	var hero_row := HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", 14)
	hero.add_child(hero_row)
	var moa_badge := MathlandUiScript.literal_label("M", 38, MathlandUiScript.DEEP_TEAL)
	moa_badge.custom_minimum_size = Vector2(58, 58)
	moa_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_row.add_child(moa_badge)
	var app_name := MathlandUiScript.label("app.title", 22, MathlandUiScript.INK)
	app_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app_name.clip_text = true
	hero_row.add_child(app_name)
	_profile_buttons = VBoxContainer.new()
	_profile_buttons.name = "ProfileList"
	_profile_buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_profile_buttons.add_theme_constant_override("separation", 6)
	body.add_child(_profile_buttons)
	_pin_input = LineEdit.new()
	_pin_input.name = "ProfilePinInput"
	_pin_input.placeholder_text = TranslationServer.translate("profile.pin.placeholder")
	_pin_input.secret = true
	_pin_input.max_length = 4
	_pin_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_pin_input.custom_minimum_size = Vector2(0, 48)
	_pin_input.add_theme_font_size_override("font_size", 18)
	body.add_child(_pin_input)
	_error_label = MathlandUiScript.literal_label("", 15, MathlandUiScript.CORAL)
	_error_label.custom_minimum_size = Vector2(0, 20)
	body.add_child(_error_label)
	_unlock_button = MathlandUiScript.tactile_button("UnlockButton", "profile.unlock", "arrow_right", Vector2(0, 56), 18)
	body.add_child(_unlock_button)
	_connect_tactile(_unlock_button, _unlock_selected)
	var create_button := MathlandUiScript.tactile_button("CreateProfileButton", "profile.create", "star", Vector2(0, 56), 18)
	body.add_child(create_button)
	_connect_tactile(create_button, show_create_dialog)
	_dialog = ProfileCreateDialogScene.instantiate()
	_dialog.name = "CreateProfileDialog"
	_dialog.configure({"profile_service": _profile_service, "ui_policy": _ui_policy})
	_dialog.profile_created.connect(_on_profile_created)
	_dialog.dismissed.connect(func(): _dialog.visible = false)
	_dialog.visible = false
	add_child(_dialog)
	_refresh_profiles()

func attempt_unlock(profile_id: String, pin: String, now_unix: int) -> Dictionary:
	if _profile_activator == null or not _profile_activator.has_method("activate_profile"):
		return _show_unlock_error({"ok": false, "error": "activation_unavailable"})
	var activation: Variant = _profile_activator.activate_profile(profile_id, pin, now_unix)
	var result: Dictionary = activation if activation is Dictionary else {"ok": false, "error": "invalid_activation_result"}
	if not result.get("ok", false):
		return _show_unlock_error(result)
	_profile_id = result.profile.profile_id
	_error_label.text = ""
	_pin_input.clear()
	var route_params: Dictionary = result.get("route_params", {}).duplicate(false)
	route_params["profile_id"] = _profile_id
	var routed := _route(AppRouteScript.ISLAND, route_params)
	if not routed.get("ok", false):
		return _show_unlock_error({"ok": false, "error": "route_failed"})
	return result.duplicate(true)

func show_create_dialog() -> void:
	_dialog.visible = true
	_dialog.move_to_front()

func _refresh_profiles() -> void:
	for child in _profile_buttons.get_children():
		child.queue_free()
	var profiles: Array = []
	if _profile_service != null and _profile_service.has_method("list_profiles"):
		profiles = _profile_service.list_profiles()
	if profiles.is_empty():
		var empty_label := MathlandUiScript.label("profile.empty", 17, MathlandUiScript.MUTED_INK)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_profile_buttons.add_child(empty_label)
		_selected_id = ""
		_unlock_button.set_enabled(false)
		return
	for index in profiles.size():
		var profile: Dictionary = profiles[index]
		var button := MathlandUiScript.tactile_button(
			"ProfileButton_%d" % index,
			"avatar.%s" % profile.avatar_id,
			"",
			Vector2(0, 54),
			18
		)
		button.configure_display_text("%s · %s" % [profile.nickname, TranslationServer.translate("avatar.%s" % profile.avatar_id)])
		_profile_buttons.add_child(button)
		_connect_tactile(button, _select_profile.bind(String(profile.profile_id)))
	if _selected_id.is_empty():
		_selected_id = profiles[0].profile_id
	_unlock_button.set_enabled(true)

func _select_profile(profile_id: String) -> void:
	_selected_id = profile_id
	_pin_input.grab_focus()

func _unlock_selected() -> void:
	if _selected_id.is_empty():
		return
	attempt_unlock(_selected_id, _pin_input.text, int(Time.get_unix_time_from_system()))

func _show_unlock_error(result: Dictionary) -> Dictionary:
	var error := String(result.get("error", "save_failed"))
	if error == "invalid_pin":
		error = "invalid_pin_attempt"
	if error not in ["invalid_pin_attempt", "pin_locked", "save_failed"]:
		error = "activation_failed"
	_error_label.text = TranslationServer.translate("profile.error.%s" % error)
	return result.duplicate(true)

func _on_profile_created(profile: Dictionary) -> void:
	_selected_id = profile.profile_id
	_dialog.visible = false
	_refresh_profiles()
	_play_effect(&"collection", size * 0.5)
