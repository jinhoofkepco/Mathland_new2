class_name EffectCatalog
extends RefCounted

const EFFECT_NAMES: Array[StringName] = [
	&"correct",
	&"wrong",
	&"combo_1",
	&"combo_2",
	&"boss",
	&"health_loss",
	&"target_reached",
	&"level_up",
	&"health_depleted",
	&"reward",
	&"collection",
	&"coupon",
]

var _presets: Dictionary = {}

func _init() -> void:
	_presets = {
		&"correct": _preset(24, 0.42, 3.0, 12.0, 0.18, Color("52d6a0"), "✓", &"effect.correct.caption"),
		&"wrong": _preset(12, 0.32, 5.0, 6.0, 0.16, Color("ff7b7b"), "↻", &"effect.wrong.caption"),
		&"combo_1": _preset(36, 0.50, 5.0, 18.0, 0.22, Color("ffd166"), "✦", &"effect.combo_1.caption"),
		&"combo_2": _preset(52, 0.58, 7.0, 24.0, 0.25, Color("ff9f43"), "★", &"effect.combo_2.caption"),
		&"boss": _preset(72, 0.70, 9.0, 30.0, 0.28, Color("b993ff"), "♛", &"effect.boss.caption"),
		&"health_loss": _preset(16, 0.36, 6.0, 8.0, 0.18, Color("ff6b81"), "♥", &"effect.health_loss.caption"),
		&"target_reached": _preset(64, 0.68, 6.0, 26.0, 0.28, Color("4dd6e8"), "◎", &"effect.target_reached.caption"),
		&"level_up": _preset(80, 0.78, 8.0, 34.0, 0.30, Color("ffe66d"), "↑", &"effect.level_up.caption"),
		&"health_depleted": _preset(14, 0.42, 3.0, 4.0, 0.20, Color("8c9aac"), "◇", &"effect.health_depleted.caption"),
		&"reward": _preset(34, 0.52, 4.0, 20.0, 0.22, Color("ffb347"), "●", &"effect.reward.caption"),
		&"collection": _preset(42, 0.58, 5.0, 22.0, 0.24, Color("65d6ce"), "◆", &"effect.collection.caption"),
		&"coupon": _preset(56, 0.66, 6.0, 28.0, 0.26, Color("f7a8ff"), "▣", &"effect.coupon.caption"),
	}

func names() -> Array[StringName]:
	return EFFECT_NAMES.duplicate()

func has(effect_name: StringName) -> bool:
	return _presets.has(effect_name)

func get_preset(effect_name: StringName) -> Dictionary:
	if not _presets.has(effect_name):
		return {}
	return _presets[effect_name].duplicate(true)

func _preset(
	particle_count: int,
	duration: float,
	shake_amplitude: float,
	translation_amplitude: float,
	flash_duration: float,
	color: Color,
	icon: String,
	label_key: StringName
) -> Dictionary:
	return {
		"particle_count": particle_count,
		"duration": duration,
		"shake_amplitude": shake_amplitude,
		"translation_amplitude": translation_amplitude,
		"flash_duration": flash_duration,
		"color": color,
		"icon": icon,
		"label_key": label_key,
	}
