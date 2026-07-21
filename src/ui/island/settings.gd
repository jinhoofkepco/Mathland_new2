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

func _apply_live_services(changed_key: String) -> void:
	if changed_key in ["master_db", "music_db", "sfx_db", "voice_db", "voice_enabled"]:
		if _audio_service != null and _audio_service.has_method("apply_settings"):
			_audio_service.apply_settings(_settings)
	if changed_key in ["effect_quality", "reduced_motion"]:
		if _effects_service != null and _effects_service.has_method("set_policy"):
			_effects_service.set_policy(StringName(_settings.effect_quality), bool(_settings.reduced_motion))

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
