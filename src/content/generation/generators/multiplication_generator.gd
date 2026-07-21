class_name MultiplicationGenerator
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const KEYS: Array[String] = ["left_min", "left_max", "right_min", "right_max", "display"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	if (
		not _is_nonnegative_safe_integer(parameters.get("left_min"))
		or not _is_nonnegative_safe_integer(parameters.get("left_max"))
		or int(parameters.get("left_max", -1)) < int(parameters.get("left_min", 0))
	):
		issues.append("LEFT_RANGE")
	if (
		not _is_nonnegative_safe_integer(parameters.get("right_min"))
		or not _is_nonnegative_safe_integer(parameters.get("right_max"))
		or int(parameters.get("right_max", -1)) < int(parameters.get("right_min", 0))
	):
		issues.append("RIGHT_RANGE")
	if parameters.get("display") not in ["horizontal", "column"]:
		issues.append("DISPLAY")
	var left_maximum: Variant = parameters.get("left_max")
	var right_maximum: Variant = parameters.get("right_max")
	if _is_nonnegative_safe_integer(left_maximum) and _is_nonnegative_safe_integer(right_maximum):
		if int(left_maximum) > 0:
			@warning_ignore("integer_division")
			if int(right_maximum) > int(Contract.SAFE_INTEGER_MAX / int(left_maximum)):
				issues.append("OVERFLOW_RANGE")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng := SeededRngScript.new(seed)
	var operands: Array[int] = [
		rng.range_int(parameters["left_min"], parameters["left_max"]),
		rng.range_int(parameters["right_min"], parameters["right_max"]),
	]
	var answer := operands[0] * operands[1]
	return _fields(
		"question.multiplication",
		operands,
		{
			"operands": operands,
			"operator": "*",
			"display_mode": parameters["display"],
			"answer": answer,
		},
		answer
	)
