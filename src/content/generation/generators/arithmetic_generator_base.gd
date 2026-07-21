class_name ArithmeticGeneratorBase
extends "res://src/content/generation/question_generator.gd"

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const SeededRngScript = preload("res://src/content/generation/seeded_rng.gd")
const MAX_ATTEMPTS := 128

func _parameters(band: Dictionary) -> Variant:
	var value: Variant = band.get("generator_parameters")
	return value if value is Dictionary else null

func _has_exact_keys(parameters: Dictionary, expected: Array[String]) -> bool:
	var actual: Array[String] = []
	for key in parameters:
		actual.append(String(key))
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	return actual == sorted_expected

func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) >= 0
		and int(value) <= Contract.SAFE_INTEGER_MAX
	)

func _policy_accepts(policy: String, condition: bool) -> bool:
	return policy == "allow" or condition == (policy == "require")

func _addition_carries(source_operands: Array, ones_only: bool) -> bool:
	var operands := source_operands.duplicate()
	while true:
		var digit_sum := 0
		var has_more := false
		for index in operands.size():
			digit_sum += int(operands[index]) % 10
			@warning_ignore("integer_division")
			operands[index] = int(operands[index]) / 10
			has_more = has_more or int(operands[index]) > 0
		if digit_sum >= 10:
			return true
		if ones_only or not has_more:
			return false
	return false

func _subtraction_borrows(minuend: int, subtrahend: int, ones_only: bool) -> bool:
	var left := minuend
	var right := subtrahend
	while true:
		if left % 10 < right % 10:
			return true
		if ones_only:
			return false
		@warning_ignore("integer_division")
		left = left / 10
		@warning_ignore("integer_division")
		right = right / 10
		if left == 0 and right == 0:
			return false
	return false

func _fields(
	prompt_key: String,
	operands: Array,
	resolved_parameters: Dictionary,
	answer: int
) -> Dictionary:
	last_error = ""
	var operand_strings := PackedStringArray()
	for operand in operands:
		operand_strings.append(str(operand))
	return {
		"resolved_parameters": resolved_parameters.duplicate(true),
		"prompt": {"key": prompt_key, "args": {"expression": " ".join(operand_strings)}},
		"correct_answer": {"kind": "integer", "value": answer},
	}

func _invalid() -> Dictionary:
	last_error = "INVALID_PARAMETERS"
	return {}

func _unsatisfiable() -> Dictionary:
	last_error = "UNSATISFIABLE_PARAMETERS"
	return {}
