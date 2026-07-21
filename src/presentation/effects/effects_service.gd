class_name EffectsService
extends Node2D

const EffectCatalogScript = preload("res://src/presentation/effects/effect_catalog.gd")
const TransientPoolScript = preload("res://src/presentation/effects/transient_pool.gd")
const EffectBurstScene = preload("res://scenes/shared/effect_burst.tscn")
const QUALITY_MULTIPLIERS := {
	&"low": 0.25,
	&"medium": 0.60,
	&"high": 1.0,
}

var _catalog := EffectCatalogScript.new()
var _pool: Node
var _quality: StringName = &"high"
var _reduced_motion := false
var _latest_burst: Node

func _ready() -> void:
	_ensure_pool()

func set_policy(quality: StringName, reduced_motion: bool) -> bool:
	if not QUALITY_MULTIPLIERS.has(quality):
		return false
	_quality = quality
	_reduced_motion = reduced_motion
	return true

func play(effect_name: StringName, at: Vector2) -> bool:
	var preset := _catalog.get_preset(effect_name)
	if preset.is_empty():
		return false
	if not _ensure_pool():
		return false
	var burst: Node = _pool.acquire()
	if burst == null:
		return false
	_latest_burst = burst
	burst.play(preset, at, QUALITY_MULTIPLIERS[_quality], _reduced_motion)
	return true

func latest_burst() -> Node:
	return _latest_burst

func total_created() -> int:
	return _pool.total_created() if _pool != null else 0

func active_count() -> int:
	return _pool.active_count() if _pool != null else 0

func available_count() -> int:
	return _pool.available_count() if _pool != null else 0

func _ensure_pool() -> bool:
	if _pool != null:
		return true
	_pool = TransientPoolScript.new()
	_pool.name = "TransientPool"
	add_child(_pool)
	if not _pool.configure(EffectBurstScene, 8):
		_pool.queue_free()
		_pool = null
		return false
	return true
