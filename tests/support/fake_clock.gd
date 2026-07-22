class_name FakeClock
extends "res://src/core/clock.gd"

var _now_ms := 0

func _init(initial_ms: int = 0) -> void:
	_now_ms = maxi(initial_ms, 0)

func now_ms() -> int:
	return _now_ms

func advance_ms(delta_ms: int) -> void:
	assert(delta_ms >= 0, "a monotonic fake clock cannot move backwards")
	_now_ms += delta_ms
