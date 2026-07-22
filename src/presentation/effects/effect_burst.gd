class_name EffectBurst
extends Node2D

signal finished(burst: Node)

@onready var _particles: CPUParticles2D = $Particles
@onready var _visual: Node2D = $Visual
@onready var _glow: Polygon2D = $Visual/Glow
@onready var _icon: Label = $Visual/Icon
@onready var _label: Label = $Visual/Caption

var active := false
var configured_particle_count := 0
var configured_shake_amplitude := 0.0
var configured_translation_amplitude := 0.0
var configured_flash_duration := 0.0
var _animation: Tween

func _ready() -> void:
	reset_for_pool()

func play(preset: Dictionary, at: Vector2, particle_multiplier: float, reduced_motion: bool) -> void:
	_stop_animation()
	active = true
	visible = true
	position = at
	configured_particle_count = maxi(1, int(floor(preset.particle_count * clampf(particle_multiplier, 0.0, 1.0))))
	configured_shake_amplitude = 0.0 if reduced_motion else float(preset.shake_amplitude)
	configured_translation_amplitude = 0.0 if reduced_motion else float(preset.translation_amplitude)
	configured_flash_duration = maxf(float(preset.flash_duration), 0.01)
	var duration := maxf(float(preset.duration), configured_flash_duration)
	var color: Color = preset.color
	_particles.amount = configured_particle_count
	_particles.modulate = color
	_particles.restart()
	_particles.emitting = true
	_glow.color = Color(color, 0.24)
	_icon.text = preset.icon
	_label.text = tr(StringName(preset.label_key))
	_icon.visible = true
	_label.visible = true
	_visual.modulate = Color.WHITE
	_visual.scale = Vector2.ONE if reduced_motion else Vector2(0.72, 0.72)
	_visual.position = Vector2.ZERO if reduced_motion else Vector2(0, configured_translation_amplitude)
	_visual.rotation = 0.0 if reduced_motion else deg_to_rad(minf(configured_shake_amplitude, 10.0))
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animation.tween_property(_visual, "scale", Vector2.ONE, configured_flash_duration)
	_animation.parallel().tween_property(_visual, "position", Vector2.ZERO, configured_flash_duration)
	_animation.parallel().tween_property(_visual, "rotation", 0.0, configured_flash_duration)
	_animation.tween_interval(maxf(duration - configured_flash_duration, 0.0))
	_animation.tween_callback(_complete)

func finish_now() -> void:
	if not active:
		return
	_stop_animation()
	_complete()

func reset_for_pool() -> void:
	_stop_animation()
	active = false
	visible = false
	configured_particle_count = 0
	configured_shake_amplitude = 0.0
	configured_translation_amplitude = 0.0
	configured_flash_duration = 0.0
	if is_node_ready():
		_particles.emitting = false
		_visual.position = Vector2.ZERO
		_visual.scale = Vector2.ONE
		_visual.rotation = 0.0
		_visual.modulate = Color.WHITE

func _complete() -> void:
	if not active:
		return
	active = false
	visible = false
	_particles.emitting = false
	finished.emit(self)

func _stop_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null
