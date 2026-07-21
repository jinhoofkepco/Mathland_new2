extends Control

signal profile_created(profile: Dictionary)
signal dismissed

const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")
const ProfileRecordScript = preload("res://src/profiles/profile_record.gd")

var _profile_service: Variant
var _nickname: LineEdit
var _avatar: OptionButton
var _pin: LineEdit
var _error_label: Label
var _ui_policy: Variant
var _audio_service: Variant

func configure(params: Dictionary) -> void:
	_profile_service = params.get("profile_service")
	_ui_policy = params.get("ui_policy")
	_audio_service = params.get("audio_service")

func _ready() -> void:
	_build_ui()

func submit_values(nickname: Variant, avatar_id: Variant, pin: Variant) -> Dictionary:
	if _profile_service == null or not _profile_service.has_method("create_profile"):
		return _show_result({"ok": false, "error": "save_failed"})
	return _show_result(_profile_service.create_profile(nickname, avatar_id, pin))

func set_form_values(nickname: String, avatar_id: String, pin: String) -> void:
	_nickname.text = nickname
	_pin.text = pin
	for index in _avatar.item_count:
		if _avatar.get_item_metadata(index) == avatar_id:
			_avatar.select(index)
			break

func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.18, 0.2, 0.45)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 14
	center.offset_right = -14
	center.offset_top = 14
	center.offset_bottom = -14
	add_child(center)
	var card := MathlandUiScript.card("CreateProfileCard", MathlandUiScript.CREAM, 24)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	var title := MathlandUiScript.label("profile.create.title", 27, MathlandUiScript.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_nickname = LineEdit.new()
	_nickname.name = "NicknameInput"
	_nickname.placeholder_text = TranslationServer.translate("profile.nickname")
	_nickname.max_length = 16
	_nickname.custom_minimum_size = Vector2(0, 48)
	_nickname.add_theme_font_size_override("font_size", 18)
	column.add_child(_nickname)
	_avatar = OptionButton.new()
	_avatar.name = "AvatarInput"
	_avatar.custom_minimum_size = Vector2(0, 48)
	_avatar.add_theme_font_size_override("font_size", 17)
	for avatar_id in ProfileRecordScript.AVATAR_IDS:
		_avatar.add_item(TranslationServer.translate("avatar.%s" % avatar_id))
		_avatar.set_item_metadata(_avatar.item_count - 1, avatar_id)
	column.add_child(_avatar)
	_pin = LineEdit.new()
	_pin.name = "PinInput"
	_pin.placeholder_text = TranslationServer.translate("profile.pin.placeholder")
	_pin.secret = true
	_pin.max_length = 4
	_pin.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_pin.custom_minimum_size = Vector2(0, 48)
	_pin.add_theme_font_size_override("font_size", 18)
	column.add_child(_pin)
	_error_label = MathlandUiScript.literal_label("", 15, MathlandUiScript.CORAL)
	_error_label.name = "CreateErrorLabel"
	_error_label.custom_minimum_size = Vector2(0, 24)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_error_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var close_button := MathlandUiScript.tactile_button("CloseButton", "ui.close", "", Vector2(0, 52), 17)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(close_button)
	var save_button := MathlandUiScript.tactile_button("SaveProfileButton", "ui.save", "check", Vector2(0, 52), 17)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(save_button)
	MathlandUiScript.connect_tactile(close_button, _dismiss, _audio_service)
	MathlandUiScript.connect_tactile(save_button, _submit_form, _audio_service)
	if _ui_policy != null and _ui_policy.has_method("register_tactile"):
		_ui_policy.register_tactile(close_button)
		_ui_policy.register_tactile(save_button)

func _submit_form() -> void:
	var avatar_id: Variant = _avatar.get_item_metadata(_avatar.selected)
	submit_values(_nickname.text, avatar_id, _pin.text)

func _dismiss() -> void:
	visible = false
	dismissed.emit()

func _show_result(result: Dictionary) -> Dictionary:
	if result.get("ok", false):
		if _error_label != null:
			_error_label.text = ""
		profile_created.emit(result.profile.duplicate(true))
		return result.duplicate(true)
	var error := String(result.get("error", "save_failed"))
	if _error_label != null:
		var key := "profile.error.%s" % error
		_error_label.text = TranslationServer.translate(key)
	return result.duplicate(true)
