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
		&"correct": _preset(24, 0.42, 3.0, 12.0, 0.18, Color("52d6a0"), "✓", "정답!"),
		&"wrong": _preset(12, 0.32, 5.0, 6.0, 0.16, Color("ff7b7b"), "↻", "다시 해보자"),
		&"combo_1": _preset(36, 0.50, 5.0, 18.0, 0.22, Color("ffd166"), "✦", "연속 정답!"),
		&"combo_2": _preset(52, 0.58, 7.0, 24.0, 0.25, Color("ff9f43"), "★", "놀라워!"),
		&"boss": _preset(72, 0.70, 9.0, 30.0, 0.28, Color("b993ff"), "♛", "보스 성공!"),
		&"health_loss": _preset(16, 0.36, 6.0, 8.0, 0.18, Color("ff6b81"), "♥", "하트 -1"),
		&"target_reached": _preset(64, 0.68, 6.0, 26.0, 0.28, Color("4dd6e8"), "◎", "목표 달성!"),
		&"level_up": _preset(80, 0.78, 8.0, 34.0, 0.30, Color("ffe66d"), "↑", "레벨 업!"),
		&"health_depleted": _preset(14, 0.42, 3.0, 4.0, 0.20, Color("8c9aac"), "◇", "도전 종료"),
		&"reward": _preset(34, 0.52, 4.0, 20.0, 0.22, Color("ffb347"), "●", "사과 획득!"),
		&"collection": _preset(42, 0.58, 5.0, 22.0, 0.24, Color("65d6ce"), "◆", "새 발견!"),
		&"coupon": _preset(56, 0.66, 6.0, 28.0, 0.26, Color("f7a8ff"), "▣", "쿠폰 획득!"),
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
	label: String
) -> Dictionary:
	return {
		"particle_count": particle_count,
		"duration": duration,
		"shake_amplitude": shake_amplitude,
		"translation_amplitude": translation_amplitude,
		"flash_duration": flash_duration,
		"color": color,
		"icon": icon,
		"label": label,
	}
