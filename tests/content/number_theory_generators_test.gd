extends "res://tests/support/test_case.gd"

const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const FIXTURE_PATH := "res://tests/content/fixtures/number_theory_generator_cases.json"

func run(_tree: SceneTree) -> void:
	_test_fixed_seed_parity()
	_test_lcm_properties()
	_test_prime_factor_properties()
	_test_invalid_and_unsatisfiable_fail_closed()

func _test_fixed_seed_parity() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	for fixture_value in fixtures:
		var fixture: Dictionary = fixture_value
		var generator: Variant = GeneratorRegistryScript.new().create(fixture["generator_id"])
		assert_not_null(generator, fixture["name"])
		var parameters: Dictionary = _normalize_numbers(fixture["parameters"])
		assert_eq(generator.validate_parameters(parameters), PackedStringArray(), fixture["name"])
		var generated: Dictionary = generator.generate(
			{}, {"generator_parameters": parameters}, int(fixture["seed"])
		)
		assert_eq(generated, _normalize_numbers(fixture["expected"]), fixture["name"])

func _test_lcm_properties() -> void:
	var parameters := {
		"operand_count": 3,
		"operand_min": 2,
		"operand_max": 30,
		"require_distinct": true,
	}
	var generator: Variant = GeneratorRegistryScript.new().create("common_multiple_v1")
	for seed in range(1, 1001):
		var generated: Dictionary = generator.generate({}, {"generator_parameters": parameters}, seed)
		assert_false(generated.is_empty(), "LCM seed %d" % seed)
		if generated.is_empty():
			continue
		var resolved: Dictionary = generated["resolved_parameters"]
		var operands: Array = resolved["operands"]
		assert_eq(operands.size(), parameters["operand_count"])
		var seen := {}
		for operand in operands:
			assert_true(operand >= parameters["operand_min"] and operand <= parameters["operand_max"])
			seen[operand] = true
		assert_eq(seen.size(), parameters["operand_count"])
		assert_eq(resolved["operator"], "lcm")
		assert_eq(resolved["answer"], _lcm(operands))
		assert_true(resolved["answer"] <= 9007199254740991)
		assert_eq(generated["correct_answer"], {"kind":"integer","value":resolved["answer"]})

func _test_prime_factor_properties() -> void:
	var parameters := {
		"value_min": 4,
		"value_max": 20000,
		"factor_count_min": 2,
		"factor_count_max": 5,
		"allowed_primes": [2, 3, 5, 7],
	}
	var generator: Variant = GeneratorRegistryScript.new().create("prime_factorization_v1")
	for seed in range(1, 1001):
		var generated: Dictionary = generator.generate({}, {"generator_parameters": parameters}, seed)
		assert_false(generated.is_empty(), "prime factor seed %d" % seed)
		if generated.is_empty():
			continue
		var resolved: Dictionary = generated["resolved_parameters"]
		var factors: Array = resolved["factors"]
		assert_true(resolved["value"] >= parameters["value_min"])
		assert_true(resolved["value"] <= parameters["value_max"])
		assert_eq(factors.size(), resolved["factor_count"])
		assert_true(resolved["factor_count"] >= parameters["factor_count_min"])
		assert_true(resolved["factor_count"] <= parameters["factor_count_max"])
		var product := 1
		for index in factors.size():
			assert_true(factors[index] in parameters["allowed_primes"])
			if index > 0:
				assert_true(factors[index - 1] <= factors[index])
			product *= int(factors[index])
		assert_eq(resolved["value"], product)
		assert_eq(resolved["allowed_primes"], parameters["allowed_primes"])
		assert_eq(
			generated["correct_answer"],
			{"kind":"integer_list","values":factors,"order_matters":false}
		)

func _test_invalid_and_unsatisfiable_fail_closed() -> void:
	var lcm_generator: Variant = GeneratorRegistryScript.new().create("common_multiple_v1")
	assert_false(lcm_generator.validate_parameters({"operand_count": 4}).is_empty())
	var no_distinct: Dictionary = lcm_generator.generate(
		{},
		{"generator_parameters":{"operand_count":3,"operand_min":2,"operand_max":3,"require_distinct":true}},
		1
	)
	assert_eq(no_distinct, {})
	assert_eq(lcm_generator.last_error, "UNSATISFIABLE_PARAMETERS")

	var factor_generator: Variant = GeneratorRegistryScript.new().create("prime_factorization_v1")
	assert_false(factor_generator.validate_parameters({
		"value_min":2,"value_max":9007199254740992,"factor_count_min":1,
		"factor_count_max":2,"allowed_primes":[2,4,2]
	}).is_empty())
	var impossible: Dictionary = factor_generator.generate(
		{},
		{"generator_parameters":{"value_min":17,"value_max":17,"factor_count_min":2,"factor_count_max":2,"allowed_primes":[2,3]}},
		1
	)
	assert_eq(impossible, {})
	assert_eq(factor_generator.last_error, "UNSATISFIABLE_PARAMETERS")

func _gcd(left: int, right: int) -> int:
	var a := left
	var b := right
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a

func _lcm(operands: Array) -> int:
	var answer := 1
	for operand in operands:
		answer = (answer / _gcd(answer, int(operand))) * int(operand)
	return answer

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
