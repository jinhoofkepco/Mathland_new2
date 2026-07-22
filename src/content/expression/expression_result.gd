class_name MathlandExpressionResult
extends RefCounted

var ok: bool
var value: int
var error_code: String
var offset: int

func _init(
	is_ok: bool = false,
	result_value: int = 0,
	result_error_code: String = "",
	result_offset: int = -1
) -> void:
	ok = is_ok
	value = result_value
	error_code = result_error_code
	offset = result_offset
