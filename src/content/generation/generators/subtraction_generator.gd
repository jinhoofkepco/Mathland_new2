class_name SubtractionGenerator
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const KEYS: Array[String] = [
	"operand_count", "operand_min", "operand_max", "place_mode", "borrow", "allow_negative",
]

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
	if parameters.get("borrow") not in ["allow", "forbid", "require"]:
		issues.append("BORROW_POLICY")
	if parameters.get("allow_negative") != false:
		issues.append("ALLOW_NEGATIVE")
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
	var rng := SeededRngScript.new(seed)
	for _attempt in MAX_ATTEMPTS:
		var operands: Array[int] = []
		for _index in int(parameters["operand_count"]):
			operands.append(rng.range_int(parameters["operand_min"], parameters["operand_max"]))
		var subtrahend := 0
		for index in range(1, operands.size()):
			subtrahend += operands[index]
		var answer := operands[0] - subtrahend
		if answer < 0:
			continue
		var borrow := _subtraction_borrows(
			operands[0], subtrahend, parameters["place_mode"] == "ones_digit"
		)
		if not _policy_accepts(parameters["borrow"], borrow):
			continue
		return _fields(
			"question.subtraction",
			operands,
			{
				"operands": operands,
				"operator": "-",
				"borrow": borrow,
				"display_mode": parameters["place_mode"],
				"answer": answer,
			},
			answer
		)
	return _unsatisfiable()
