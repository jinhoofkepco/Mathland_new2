extends "res://tests/support/test_case.gd"

const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")
const IDS := ["addition_ones", "subtraction_ones", "multiplication", "common_multiples_lcm", "prime_factorization"]

func run(_tree: SceneTree) -> void:
	for activity_id in IDS:
		var source := _load_source(activity_id)
		assert_false(source.is_empty(), activity_id)
		if source.is_empty():
			continue
		for band_value in source.difficulty_bands:
			var band: Dictionary = band_value
			var generator: Variant = GeneratorRegistryScript.new().create(band.generator_id)
			for sample_value in source.validation_samples:
				var sample: Dictionary = sample_value
				if sample.band_id != band.band_id:
					continue
				var generated: Dictionary = generator.generate(source, band, int(sample.seed))
				assert_eq(generated.get("correct_answer"), sample.expected_answer, "%s/%s/%s" % [activity_id, band.band_id, sample.seed])
				if generated.is_empty():
					continue
				assert_true(_independent_answer(generated["resolved_parameters"], band.generator_id, generated["correct_answer"]))

func _load_source(activity_id: String) -> Dictionary:
	var path := "res://content/sources/%s.json" % activity_id
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = ContentValidatorScript.new().parse_json(FileAccess.get_file_as_string(path), path)
	return parsed.value if parsed.ok and parsed.value is Dictionary else {}

func _independent_answer(resolved: Dictionary, generator_id: String, answer: Dictionary) -> bool:
	if generator_id == "prime_factorization_v1":
		var product := 1
		for factor in answer.get("values", []):
			product *= int(factor)
		return product == int(resolved.get("value", -1))
	if generator_id == "common_multiple_v1":
		var value := int(answer.get("value", -1))
		if value < 1:
			return false
		for operand in resolved.get("operands", []):
			if value % int(operand) != 0:
				return false
		return true
	var operands: Array = resolved.get("operands", [])
	if operands.size() != 2 and generator_id != "addition_v1" and generator_id != "subtraction_v1":
		return false
	var expected: int
	if generator_id == "addition_v1":
		expected = 0
		for operand in operands:
			expected += int(operand)
	elif generator_id == "subtraction_v1":
		expected = int(operands[0])
		for index in range(1, operands.size()):
			expected -= int(operands[index])
	else:
		expected = int(operands[0]) * int(operands[1])
	return answer.get("value") == expected
