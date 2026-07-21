extends "res://tests/support/test_case.gd"

const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const FIXTURE_PATH := "res://tests/content/fixtures/arithmetic_generator_cases.json"

func run(_tree: SceneTree) -> void:
	_test_fixed_seed_parity()
	_test_addition_properties()
	_test_subtraction_properties()
	_test_multiplication_properties()
	_test_unsatisfiable_parameters_fail_closed()

func _test_fixed_seed_parity() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	for fixture_value in fixtures:
		var fixture: Dictionary = fixture_value
		var generator: Variant = GeneratorRegistryScript.new().create(fixture["generator_id"])
		assert_not_null(generator, fixture["name"])
		var generated: Dictionary = generator.generate(
			{}, {"generator_parameters": _normalize_numbers(fixture["parameters"])}, int(fixture["seed"])
		)
		assert_eq(generated["resolved_parameters"], _normalize_numbers(fixture["expected"]), fixture["name"])
		assert_eq(
			generated["correct_answer"],
			{"kind": "integer", "value": int(fixture["expected"]["answer"])},
			fixture["name"]
		)

func _test_addition_properties() -> void:
	var cases := [
		{"operand_count":2,"operand_min":0,"operand_max":99,"place_mode":"full","carry":"allow"},
		{"operand_count":2,"operand_min":0,"operand_max":9,"place_mode":"ones_digit","carry":"forbid"},
		{"operand_count":3,"operand_min":0,"operand_max":9,"place_mode":"ones_digit","carry":"require"},
	]
	for parameters in cases:
		var generator: Variant = GeneratorRegistryScript.new().create("addition_v1")
		for seed in range(1, 1001):
			var generated: Dictionary = generator.generate({}, {"generator_parameters": parameters}, seed)
			assert_false(generated.is_empty(), "addition seed %d" % seed)
			if generated.is_empty():
				continue
			var resolved: Dictionary = generated["resolved_parameters"]
			var operands: Array = resolved["operands"]
			assert_eq(operands.size(), parameters["operand_count"])
			var answer := 0
			for operand in operands:
				assert_true(operand >= parameters["operand_min"] and operand <= parameters["operand_max"])
				answer += operand
			assert_eq(resolved["answer"], answer)
			var carries := _addition_carries(operands, parameters["place_mode"] == "ones_digit")
			assert_eq(resolved["carry"], carries)
			if parameters["carry"] != "allow":
				assert_eq(carries, parameters["carry"] == "require")

func _test_subtraction_properties() -> void:
	var cases := [
		{"operand_count":3,"operand_min":0,"operand_max":99,"place_mode":"full","borrow":"allow","allow_negative":false},
		{"operand_count":2,"operand_min":0,"operand_max":19,"place_mode":"ones_digit","borrow":"forbid","allow_negative":false},
		{"operand_count":2,"operand_min":0,"operand_max":99,"place_mode":"full","borrow":"require","allow_negative":false},
	]
	for parameters in cases:
		var generator: Variant = GeneratorRegistryScript.new().create("subtraction_v1")
		for seed in range(1, 1001):
			var generated: Dictionary = generator.generate({}, {"generator_parameters": parameters}, seed)
			assert_false(generated.is_empty(), "subtraction seed %d" % seed)
			if generated.is_empty():
				continue
			var resolved: Dictionary = generated["resolved_parameters"]
			var operands: Array = resolved["operands"]
			assert_eq(operands.size(), parameters["operand_count"])
			var left := int(operands[0])
			var subtrahend := 0
			for index in range(1, operands.size()):
				assert_true(
					operands[index] >= parameters["operand_min"]
					and operands[index] <= parameters["operand_max"]
				)
				subtrahend += int(operands[index])
			assert_true(left >= parameters["operand_min"] and left <= parameters["operand_max"])
			assert_eq(resolved["answer"], left - subtrahend)
			assert_true(resolved["answer"] >= 0)
			var borrows := _subtraction_borrows(
				left, subtrahend, parameters["place_mode"] == "ones_digit"
			)
			assert_eq(resolved["borrow"], borrows)
			if parameters["borrow"] != "allow":
				assert_eq(borrows, parameters["borrow"] == "require")

func _test_multiplication_properties() -> void:
	var parameters := {"left_min":2,"left_max":12,"right_min":2,"right_max":9,"display":"column"}
	var generator: Variant = GeneratorRegistryScript.new().create("multiplication_v1")
	for seed in range(1, 1001):
		var generated: Dictionary = generator.generate({}, {"generator_parameters": parameters}, seed)
		assert_false(generated.is_empty(), "multiplication seed %d" % seed)
		if generated.is_empty():
			continue
		var resolved: Dictionary = generated["resolved_parameters"]
		var left := int(resolved["operands"][0])
		var right := int(resolved["operands"][1])
		assert_true(left >= 2 and left <= 12)
		assert_true(right >= 2 and right <= 9)
		assert_eq(resolved["answer"], left * right)

func _test_unsatisfiable_parameters_fail_closed() -> void:
	var generator: Variant = GeneratorRegistryScript.new().create("addition_v1")
	var generated: Dictionary = generator.generate(
		{},
		{"generator_parameters":{"operand_count":2,"operand_min":0,"operand_max":4,"place_mode":"ones_digit","carry":"require"}},
		1
	)
	assert_eq(generated, {})
	assert_eq(generator.last_error, "UNSATISFIABLE_PARAMETERS")

func _addition_carries(source_operands: Array, ones_only: bool) -> bool:
	var operands: Array = source_operands.duplicate()
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

func _normalize_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and value == floor(value):
		return int(value)
	if value is Array:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_normalize_numbers(item))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary := {}
		for key in value:
			normalized_dictionary[key] = _normalize_numbers(value[key])
		return normalized_dictionary
	return value
