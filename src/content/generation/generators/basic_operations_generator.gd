class_name BasicOperationsGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["operators", "operand_min", "operand_max", "allow_negative"]
const MAX_BASIC_RESULT := 100

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var operators: Variant = parameters.get("operators")
	if operators not in ["addition", "subtraction", "mixed"]:
		issues.append("OPERATORS")
	var minimum: Variant = parameters.get("operand_min")
	var maximum: Variant = parameters.get("operand_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(maximum) < int(minimum)
		or int(maximum) > MAX_BASIC_RESULT
	):
		issues.append("OPERAND_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("OPERAND_RANGE_WIDTH")
	if parameters.get("allow_negative") != false:
		issues.append("ALLOW_NEGATIVE")
	if (
		operators in ["addition", "mixed"]
		and _is_nonnegative_safe_integer(minimum)
		and _is_nonnegative_safe_integer(maximum)
		and int(minimum) > int(maximum) / 2
	):
		issues.append("ADDITION_RANGE")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var operator: String
	if parameters["operators"] == "mixed":
		operator = "+" if rng.range_int(0, 1) == 0 else "-"
	else:
		operator = "+" if parameters["operators"] == "addition" else "-"
	var minimum: int = parameters["operand_min"]
	var maximum: int = parameters["operand_max"]
	var left: int
	var right: int
	if operator == "+":
		left = rng.range_int(minimum, maximum - minimum)
		right = rng.range_int(minimum, maximum - left)
	else:
		left = rng.range_int(minimum, maximum)
		right = rng.range_int(minimum, left)
	var answer := left + right if operator == "+" else left - right
	var operands: Array[int] = [left, right]
	return _foundation_fields(
		{
			"operands": operands,
			"operator": operator,
			"answer": answer,
			"initial_counts": operands.duplicate(),
			"manipulative_id": "counters",
		},
		"question.basic_operations",
		{"expression": "%d %s %d" % [left, operator, right]},
		answer
	)
