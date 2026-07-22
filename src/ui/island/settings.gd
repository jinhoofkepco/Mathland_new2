extends "res://src/ui/shared/child_screen.gd"

const BOOLEAN_CONTROLS := {
	"adaptive_difficulty": ["AdaptiveToggle", "settings.adaptive"],
	"timing_aids": ["TimingAidsToggle", "settings.timing_aids"],
	"timers_enabled": ["TimersToggle", "settings.timers"],
	"reduced_motion": ["ReducedMotionToggle", "settings.reduced_motion"],
	"voice_enabled": ["VoiceEnabledToggle", "settings.voice_enabled"],
}
const VOLUME_CONTROLS := {
	"master_db": ["MasterVolume", "settings.master"],
	"music_db": ["MusicVolume", "settings.music"],
	"sfx_db": ["SfxVolume", "settings.sfx"],
	"voice_db": ["VoiceVolume", "settings.voice"],
}

var _settings: Dictionary = {}
var _controls: Dictionary = {}
var _updating_controls := false
var _pairing_input: LineEdit
var _pairing_status: Label
var _pairing_button: Control
var _re_pairing_button: Control
var _pairing_in_flight := false
var _pending_re_pair_code := ""

func _ready() -> void:
	_settings = _profile().get("settings", {}).duplicate(true)
	var ui := MathlandUiScript.scaffold(self, "settings.title", "settings.subtitle", true)
	_connect_tactile(ui.back_button, _back)
	var body: VBoxContainer = ui.body
	body.add_child(MathlandUiScript.section_label("settings.learning"))
	_add_boolean(body, "adaptive_difficulty")
	_add_boolean(body, "timing_aids")
	_add_boolean(body, "timers_enabled")
	body.add_child(MathlandUiScript.section_label("settings.presentation"))
	_add_boolean(body, "reduced_motion")
	_add_quality(body)
	body.add_child(MathlandUiScript.section_label("settings.audio"))
	_add_boolean(body, "voice_enabled")
	for key in ["master_db", "music_db", "sfx_db", "voice_db"]:
		_add_volume(body, key)
	body.add_child(MathlandUiScript.section_label("settings.remote_monitoring"))
	_add_pairing(body)
	_refresh_controls()

func current_settings() -> Dictionary:
	return _settings.duplicate(true)

func apply_setting(key: String, value: Variant) -> bool:
	if _profile_service == null or not _profile_service.has_method("update_settings") or _profile_id.is_empty():
		return false
	var error: Error = _profile_service.update_settings(_profile_id, {key: value})
	if error != OK:
		_refresh_controls()
		return false
	var profile: Dictionary = _profile_service.get_profile(_profile_id)
	_settings = profile.get("settings", {}).duplicate(true)
	_apply_live_services(key)
	_refresh_controls()
	return true

func submit_pairing_code(code: String) -> Dictionary:
	if _pairing_in_flight:
		return {"ok": false, "error": "pairing_in_progress"}
	_pending_re_pair_code = ""
	if _re_pairing_button != null:
		_re_pairing_button.visible = false
	if _pairing_input != null:
		_pairing_input.text = ""
	if not _is_six_digit_code(code):
		_set_pairing_status("settings.pairing.invalid", true)
		return {"ok": false, "error": "invalid_pairing_code"}
	var sync_service: Variant = _params.get("sync_service")
	if sync_service == null or not sync_service.has_method("pair_device"):
		_set_pairing_status("settings.pairing.unavailable", true)
		return {"ok": false, "error": "pairing_unavailable"}
	var profile := _profile()
	var display_name := String(profile.get("nickname", "")).strip_edges()
	if display_name.is_empty():
		_set_pairing_status("settings.pairing.failed", true)
		return {"ok": false, "error": "invalid_pairing_context"}
	_pairing_in_flight = true
	_set_pairing_enabled(false)
	_set_pairing_status("settings.pairing.connecting", false)
	var result: Variant = await sync_service.pair_device(code, _profile_id, display_name)
	_pairing_in_flight = false
	_set_pairing_enabled(true)
	if not result is Dictionary:
		_set_pairing_status("settings.pairing.failed", true)
		return {"ok": false, "error": "invalid_pairing_result"}
	var pairing_result: Dictionary = result
	if pairing_result.get("ok", false):
		_set_pairing_status("settings.pairing.connected", false)
	else:
		var error := String(pairing_result.get("error", ""))
		if error == "re_pair_required":
			_pending_re_pair_code = code
			if _re_pairing_button != null:
				_re_pairing_button.visible = true
		_set_pairing_status(_pairing_error_key(error), true)
	return pairing_result.duplicate(true)

func confirm_re_pair() -> Dictionary:
	if _pairing_in_flight:
		return {"ok": false, "error": "pairing_in_progress"}
	if _pending_re_pair_code.is_empty():
		return {"ok": false, "error": "re_pair_not_required"}
	var sync_service: Variant = _params.get("sync_service")
	if sync_service == null or not sync_service.has_method("re_pair_device"):
		_set_pairing_status("settings.pairing.unavailable", true)
		return {"ok": false, "error": "pairing_unavailable"}
	var display_name := String(_profile().get("nickname", "")).strip_edges()
	if display_name.is_empty():
		_set_pairing_status("settings.pairing.failed", true)
		return {"ok": false, "error": "invalid_pairing_context"}
	var code := _pending_re_pair_code
	_pending_re_pair_code = ""
	if _re_pairing_button != null:
		_re_pairing_button.visible = false
	_pairing_in_flight = true
	_set_pairing_enabled(false)
	_set_pairing_status("settings.pairing.connecting", false)
	var result: Variant = await sync_service.re_pair_device(code, _profile_id, display_name)
	_pairing_in_flight = false
	_set_pairing_enabled(true)
	if not result is Dictionary:
		_set_pairing_status("settings.pairing.failed", true)
		return {"ok": false, "error": "invalid_pairing_result"}
	var pairing_result: Dictionary = result
	_set_pairing_status(
		"settings.pairing.connected"
		if pairing_result.get("ok", false)
		else _pairing_error_key(String(pairing_result.get("error", ""))),
		not pairing_result.get("ok", false),
	)
	return pairing_result.duplicate(true)

func _add_boolean(body: VBoxContainer, key: String) -> void:
	var control_info: Array = BOOLEAN_CONTROLS[key]
	var button := CheckButton.new()
	button.name = control_info[0]
	button.text = TranslationServer.translate(control_info[1])
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MathlandUiScript.style_check_button(button)
	button.toggled.connect(func(value: bool):
		if not _updating_controls:
			apply_setting(key, value)
	)
	body.add_child(button)
	_controls[key] = button

func _add_quality(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "EffectQualityRow"
	row.custom_minimum_size = Vector2(0, 48)
	body.add_child(row)
	var row_label := MathlandUiScript.label("settings.effect_quality", 17, MathlandUiScript.INK)
	row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(row_label)
	var options := OptionButton.new()
	options.name = "EffectQualityOption"
	MathlandUiScript.style_option_button(options)
	for quality in ["low", "medium", "high"]:
		options.add_item(TranslationServer.translate("settings.quality.%s" % quality))
		options.set_item_metadata(options.item_count - 1, quality)
	options.item_selected.connect(func(index: int):
		if not _updating_controls:
			apply_setting("effect_quality", options.get_item_metadata(index))
	)
	row.add_child(options)
	_controls["effect_quality"] = options

func _add_volume(body: VBoxContainer, key: String) -> void:
	var control_info: Array = VOLUME_CONTROLS[key]
	var row := HBoxContainer.new()
	row.name = "%sRow" % control_info[0]
	row.custom_minimum_size = Vector2(0, 48)
	body.add_child(row)
	var row_label := MathlandUiScript.label(control_info[1], 16, MathlandUiScript.INK)
	row_label.custom_minimum_size = Vector2(100, 48)
	row.add_child(row_label)
	var slider := HSlider.new()
	slider.name = control_info[0]
	MathlandUiScript.style_slider(slider)
	slider.value_changed.connect(func(value: float):
		if not _updating_controls:
			apply_setting(key, value)
	)
	row.add_child(slider)
	_controls[key] = slider

func _add_pairing(body: VBoxContainer) -> void:
	var helper := MathlandUiScript.label("settings.pairing.help", 15, MathlandUiScript.MUTED_INK)
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(helper)
	var row := HBoxContainer.new()
	row.name = "PairingRow"
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	_pairing_input = LineEdit.new()
	_pairing_input.name = "PairingCodeInput"
	_pairing_input.placeholder_text = TranslationServer.translate("settings.pairing.placeholder")
	_pairing_input.max_length = 6
	_pairing_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_pairing_input.secret = true
	_pairing_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pairing_input.custom_minimum_size = Vector2(120, 56)
	_pairing_input.add_theme_font_size_override("font_size", 22)
	_pairing_input.text_submitted.connect(func(_value: String): _submit_pairing_input())
	row.add_child(_pairing_input)
	_pairing_button = MathlandUiScript.tactile_button(
		"PairDeviceButton", "settings.pairing.action", "", Vector2(126, 56), 17
	)
	_connect_tactile(_pairing_button, _submit_pairing_input)
	row.add_child(_pairing_button)
	_re_pairing_button = MathlandUiScript.tactile_button(
		"RePairDeviceButton", "settings.pairing.re_pair_action", "", Vector2(0, 56), 16
	)
	_re_pairing_button.visible = false
	_connect_tactile(_re_pairing_button, _submit_re_pair)
	body.add_child(_re_pairing_button)
	_pairing_status = MathlandUiScript.label("settings.pairing.ready", 14, MathlandUiScript.MUTED_INK)
	_pairing_status.name = "PairingStatus"
	_pairing_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_pairing_status)

func _submit_pairing_input() -> void:
	if _pairing_input == null:
		return
	var code := _pairing_input.text
	await submit_pairing_code(code)

func _submit_re_pair() -> void:
	await confirm_re_pair()

func _set_pairing_enabled(enabled: bool) -> void:
	if _pairing_input != null:
		_pairing_input.editable = enabled
	if _pairing_button != null and _pairing_button.has_method("set_enabled"):
		_pairing_button.set_enabled(enabled)
	if _re_pairing_button != null and _re_pairing_button.has_method("set_enabled"):
		_re_pairing_button.set_enabled(enabled)

func _set_pairing_status(key: String, is_error: bool) -> void:
	if _pairing_status == null:
		return
	_pairing_status.text = TranslationServer.translate(key)
	_pairing_status.add_theme_color_override(
		"font_color", MathlandUiScript.CORAL if is_error else MathlandUiScript.DEEP_TEAL
	)

func _pairing_error_key(error: String) -> String:
	if error == "re_pair_required":
		return "settings.pairing.re_pair_required"
	if error in ["permission", "pairing_code_unavailable", "invalid_pairing_request"]:
		return "settings.pairing.code_failed"
	if error in ["pairing_network", "network", "authentication_network"]:
		return "settings.pairing.network"
	return "settings.pairing.failed"

func _is_six_digit_code(code: String) -> bool:
	if code.length() != 6:
		return false
	for character in code:
		if character < "0" or character > "9":
			return false
	return true

func _apply_live_services(changed_key: String) -> void:
	if changed_key in ["master_db", "music_db", "sfx_db", "voice_db", "voice_enabled"]:
		if _audio_service != null and _audio_service.has_method("apply_settings"):
			_audio_service.apply_settings(_settings)
	if changed_key in ["effect_quality", "reduced_motion"]:
		if _effects_service != null and _effects_service.has_method("set_policy"):
			_effects_service.set_policy(StringName(_settings.effect_quality), bool(_settings.reduced_motion))
	if changed_key == "reduced_motion" and _ui_policy != null and _ui_policy.has_method("set_reduced_motion"):
		_ui_policy.set_reduced_motion(bool(_settings.reduced_motion))

func _refresh_controls() -> void:
	_updating_controls = true
	for key in BOOLEAN_CONTROLS:
		var button: CheckButton = _controls.get(key)
		if button != null and _settings.has(key):
			button.set_pressed_no_signal(bool(_settings[key]))
	var options: OptionButton = _controls.get("effect_quality")
	if options != null:
		for index in options.item_count:
			if options.get_item_metadata(index) == _settings.get("effect_quality", "high"):
				options.select(index)
				break
	for key in VOLUME_CONTROLS:
		var slider: HSlider = _controls.get(key)
		if slider != null and _settings.has(key):
			slider.set_value_no_signal(float(_settings[key]))
	_updating_controls = false
