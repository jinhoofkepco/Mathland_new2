class_name AdditionGenerator
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const KEYS: Array[String] = ["operand_count", "operand_min", "operand_max", "place_mode", "carry"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	if parameters.get("operand_count") not in [2, 3]:
		issues.append("OPERAND_COUNT")
	if (
		not _is_nonnegative_safe_integer(parameters.get("operand_min"))
		or not _is_nonnegative_safe_integer(parameters.get("operand_max"))
		or int(parameters.get("operand_max", -1)) < int(parameters.get("operand_min", 0))
	):
		issues.append("OPERAND_RANGE")
	if parameters.get("place_mode") not in ["full", "ones_digit"]:
		issues.append("PLACE_MODE")
	if parameters.get("carry") not in ["allow", "forbid", "require"]:
		issues.append("CARRY_POLICY")
	if (
		_is_nonnegative_safe_integer(parameters.get("operand_min"))
		and _is_nonnegative_safe_integer(parameters.get("operand_max"))
		and int(parameters["operand_max"]) >= int(parameters["operand_min"])
		and not _is_supported_rng_range(parameters["operand_min"], parameters["operand_max"])
	):
		issues.append("OPERAND_RANGE_WIDTH")
	var count: Variant = parameters.get("operand_count")
	var maximum: Variant = parameters.get("operand_max")
	if count in [2, 3] and _is_nonnegative_safe_integer(maximum):
		@warning_ignore("integer_division")
		if int(maximum) > int(Contract.SAFE_INTEGER_MAX / int(count)):
			issues.append("OVERFLOW_RANGE")
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
		for _index in int(parameters["operand_count"]):
			operands.append(rng.range_int(parameters["operand_min"], parameters["operand_max"]))
		var carry := _addition_carries(operands, parameters["place_mode"] == "ones_digit")
		if not _policy_accepts(parameters["carry"], carry):
			continue
		var answer := 0
		for operand in operands:
			answer += operand
		return _fields(
			"question.addition",
			operands,
			{
				"operands": operands,
				"operator": "+",
				"carry": carry,
				"display_mode": parameters["place_mode"],
				"answer": answer,
			},
			answer
		)
	return _unsatisfiable()
