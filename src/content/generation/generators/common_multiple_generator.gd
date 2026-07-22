class_name CommonMultipleGenerator
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const KEYS: Array[String] = ["operand_count", "operand_min", "operand_max", "require_distinct"]
func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	if parameters.get("operand_count") not in [2, 3]:
		issues.append("OPERAND_COUNT")
	var minimum: Variant = parameters.get("operand_min")
	var maximum: Variant = parameters.get("operand_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(minimum) < 1
		or int(maximum) < int(minimum)
	):
		issues.append("OPERAND_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("OPERAND_RANGE_WIDTH")
	if typeof(parameters.get("require_distinct")) != TYPE_BOOL:
		issues.append("REQUIRE_DISTINCT")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	for _attempt in MAX_ATTEMPTS:
		var operands: Array[int] = []
		var seen := {}
		for _index in int(parameters["operand_count"]):
			var operand: int = rng.range_int(parameters["operand_min"], parameters["operand_max"])
			operands.append(operand)
			seen[operand] = true
		if parameters["require_distinct"] and seen.size() != operands.size():
			continue
		var answer := 1
		var overflowed := false
		for operand in operands:
			var divisor := _gcd(answer, operand)
			@warning_ignore("integer_division")
			var quotient := answer / divisor
			@warning_ignore("integer_division")
			if quotient > Contract.SAFE_INTEGER_MAX / operand:
				overflowed = true
				break
			answer = quotient * operand
		if overflowed:
			continue
		return _fields(
			"question.common_multiple",
			operands,
			{"operands":operands,"operator":"lcm","answer":answer},
			answer
		)
	return _unsatisfiable()

func _gcd(left: int, right: int) -> int:
	var a := left
	var b := right
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a
