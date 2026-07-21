class_name MathlandUi
extends RefCounted

const TactileButtonScene = preload("res://scenes/shared/tactile_button.tscn")

const INK := Color("173f49")
const MUTED_INK := Color("55737a")
const TEAL := Color("188793")
const DEEP_TEAL := Color("0d5f69")
const CREAM := Color("fff7df")
const SAND := Color("f6dfaa")
const CORAL := Color("ef7f66")
const SKY := Color("cceef0")
const MINT := Color("d8f2df")

static func scaffold(root: Control, title_key: String, subtitle_key: String = "", with_back := false) -> Dictionary:
	root.clip_contents = true
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.name = "IslandSkyBackground"
	background.color = Color("eaf8f4")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var sun := Panel.new()
	sun.name = "SunGlow"
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.position = Vector2(-42, -48)
	sun.size = Vector2(180, 180)
	var sun_style := StyleBoxFlat.new()
	sun_style.bg_color = Color(1.0, 0.84, 0.36, 0.22)
	sun_style.corner_radius_top_left = 90
	sun_style.corner_radius_top_right = 90
	sun_style.corner_radius_bottom_left = 90
	sun_style.corner_radius_bottom_right = 90
	sun.add_theme_stylebox_override("panel", sun_style)
	root.add_child(sun)

	var safe := MarginContainer.new()
	safe.name = "SafeMargin"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 16)
	safe.add_theme_constant_override("margin_top", 14)
	safe.add_theme_constant_override("margin_right", 16)
	safe.add_theme_constant_override("margin_bottom", 14)
	root.add_child(safe)

	var column := VBoxContainer.new()
	column.name = "ScreenColumn"
	column.add_theme_constant_override("separation", 8)
	safe.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var back_button: Control
	if with_back:
		back_button = tactile_button("BackButton", "ui.back", "", Vector2(82, 52), 18)
		header.add_child(back_button)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	header.add_child(title_column)
	var title := label(title_key, 30, INK)
	title.name = "ScreenTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_column.add_child(title)
	var subtitle: Label
	if not subtitle_key.is_empty():
		subtitle = label(subtitle_key, 15, MUTED_INK)
		subtitle.name = "ScreenSubtitle"
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_column.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	return {
		"background": background,
		"safe": safe,
		"column": column,
		"header": header,
		"title": title,
		"subtitle": subtitle,
		"scroll": scroll,
		"body": body,
		"back_button": back_button,
	}

static func tactile_button(node_name: String, label_key: String, icon_name := "", minimum := Vector2(0, 56), font_size := 19) -> Control:
	var button: Control = TactileButtonScene.instantiate()
	button.name = node_name
	button.custom_minimum_size = minimum.max(Vector2(48, 48))
	button.label_key = label_key
	button.icon_name = icon_name
	var text_label: Label = button.get_node("Visual/Content/TextLabel")
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.clip_text = true
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var icon_label: Label = button.get_node("Visual/Content/IconLabel")
	icon_label.add_theme_font_size_override("font_size", font_size + 4)
	return button

static func label(text_key: String, font_size := 18, color := INK) -> Label:
	var text_label := Label.new()
	text_label.text = TranslationServer.translate(text_key)
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.add_theme_color_override("font_color", color)
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return text_label

static func literal_label(text: String, font_size := 18, color := INK) -> Label:
	var text_label := Label.new()
	text_label.text = text
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.add_theme_color_override("font_color", color)
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return text_label

static func card(node_name: String = "Card", color := CREAM, radius := 18) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(TEAL, 0.22)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12
	style.content_margin_top = 9
	style.content_margin_right = 12
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func section_label(text_key: String) -> Label:
	var result := label(text_key, 18, DEEP_TEAL)
	result.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.65))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 1)
	return result

static func style_check_button(button: CheckButton) -> void:
	button.custom_minimum_size = Vector2(48, 48)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_pressed_color", DEEP_TEAL)

static func style_option_button(button: OptionButton) -> void:
	button.custom_minimum_size = Vector2(118, 48)
	button.add_theme_font_size_override("font_size", 16)

static func style_slider(slider: HSlider) -> void:
	slider.custom_minimum_size = Vector2(112, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = -80.0
	slider.max_value = 0.0
	slider.step = 1.0

static func connect_tactile(button: Control, callback: Callable, audio_service: Variant = null) -> void:
	button.accepted.connect(callback)
	if audio_service != null and audio_service.has_method("play_sfx"):
		button.sfx_requested.connect(func(sfx_id: StringName): audio_service.play_sfx(sfx_id))
