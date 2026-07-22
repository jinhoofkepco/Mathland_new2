class_name SystemClock
extends "res://src/core/clock.gd"

func now_ms() -> int:
	return Time.get_ticks_msec()
