extends "res://tests/support/test_case.gd"

const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const QuestionGeneratorScript = preload("res://src/content/generation/question_generator.gd")
const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const SeededRngScript = preload("res://src/content/generation/seeded_rng.gd")
const RNG_FIXTURE_PATH := "res://tests/content/fixtures/rng_vectors.json"

class TestGenerator extends QuestionGeneratorScript:
	func validate_parameters(parameters: Dictionary) -> PackedStringArray:
		return PackedStringArray() if parameters.get("maximum") == 10 else PackedStringArray(["maximum"])

	func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
		return {
			"resolved_parameters": {"draw": seed, "maximum": band["generator_parameters"]["maximum"]},
			"prompt": {"key": "activity.addition.prompt", "args": {"left": 4, "right": 3}},
			"correct_answer": {"kind": "integer", "value": 7},
		}

class TestRegistry extends GeneratorRegistryScript:
	func create(generator_id: String) -> Variant:
		return TestGenerator.new() if generator_id == "addition_v1" else null

func run(_tree: SceneTree) -> void:
	_test_rng_vector_and_helpers()
	_test_registry_allowlist()
	_test_question_envelope_is_deterministic_and_isolated()
	_test_question_engine_rejects_unknown_or_ambiguous_content()

func _test_rng_vector_and_helpers() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RNG_FIXTURE_PATH))
	var rng := SeededRngScript.new(fixture["seed"])
	var values: Array[int] = []
	for _value in fixture["values"]:
		values.append(rng.next_u32())
	assert_eq(values, _integer_array(fixture["values"]))
	assert_eq(SeededRngScript.new(0).state, int(fixture["zero_seed_normalization"]))
	rng = SeededRngScript.new(fixture["seed"])
	var ranges: Array[int] = []
	for _value in fixture["inclusive_ranges_2_5"]:
		ranges.append(rng.range_int(2, 5))
	assert_eq(ranges, _integer_array(fixture["inclusive_ranges_2_5"]))
	rng = SeededRngScript.new(fixture["seed"])
	var picks: Array[int] = []
	for _value in fixture["weighted_indices_1_3_2"]:
		picks.append(rng.weighted_index([1, 3, 2]))
	assert_eq(picks, _integer_array(fixture["weighted_indices_1_3_2"]))
	assert_eq(rng.weighted_index([]), -1)
	assert_eq(rng.range_int(5, 2), 0)

func _test_registry_allowlist() -> void:
	var registry := GeneratorRegistryScript.new()
	for generator_id in [
		"addition_v1", "subtraction_v1", "multiplication_v1", "common_multiple_v1",
		"prime_factorization_v1", "counting_v1", "number_bonds_v1", "ten_frame_v1",
		"base_ten_v1", "number_line_v1", "basic_operations_v1",
	]:
		assert_not_null(registry.create(generator_id), generator_id)
	assert_null(registry.create("remote_script"))

func _test_question_envelope_is_deterministic_and_isolated() -> void:
	var engine := QuestionEngineScript.new(TestRegistry.new())
	var activity := _activity()
	var first: Dictionary = engine.generate_question(activity, &"intro", 42)
	var second: Dictionary = engine.generate_question(activity, &"intro", 42)
	assert_eq(first, second)
	assert_eq(first["contract_version"], 1)
	assert_eq(first["activity_id"], "addition_ones")
	assert_eq(first["content_version"], "1.2.3")
	assert_eq(first["generator_id"], "addition_v1")
	assert_eq(first["band_id"], "intro")
	assert_eq(first["seed"], 42)
	assert_eq(first["correct_answer"], {"kind": "integer", "value": 7})
	first["resolved_parameters"]["maximum"] = 999
	first["answer_layout"]["id"] = "mutated"
	first["manipulative"]["config"]["maximum"] = 999
	assert_eq(engine.generate_question(activity, &"intro", 42), second)
	assert_eq(activity, _activity())

func _test_question_engine_rejects_unknown_or_ambiguous_content() -> void:
	var engine := QuestionEngineScript.new(TestRegistry.new())
	assert_eq(engine.generate_question(_activity(), &"missing", 1), {})
	assert_eq(engine.last_diagnostic, "UNKNOWN_BAND")
	var unknown_generator := _activity()
	unknown_generator["difficulty_bands"][0]["generator_id"] = "remote_script"
	assert_eq(engine.generate_question(unknown_generator, &"intro", 1), {})
	assert_eq(engine.last_diagnostic, "UNKNOWN_GENERATOR")
	var duplicate := _activity()
	duplicate["difficulty_bands"].append(duplicate["difficulty_bands"][0].duplicate(true))
	assert_eq(engine.generate_question(duplicate, &"intro", 1), {})
	assert_eq(engine.last_diagnostic, "AMBIGUOUS_BAND")
	var invalid_parameters := _activity()
	invalid_parameters["difficulty_bands"][0]["generator_parameters"]["maximum"] = 11
	assert_eq(engine.generate_question(invalid_parameters, &"intro", 1), {})
	assert_eq(engine.last_diagnostic, "INVALID_PARAMETERS")
	var invalid_band := _activity()
	invalid_band["difficulty_bands"][0].erase("manipulative")
	assert_eq(engine.generate_question(invalid_band, &"intro", 1), {})
	assert_eq(engine.last_diagnostic, "INVALID_BAND")
	assert_eq(engine.generate_question(_activity(), &"intro", -1), {})
	assert_eq(engine.last_diagnostic, "INVALID_SEED")

func _activity() -> Dictionary:
	return {
		"schema_version": 1,
		"activity_id": "addition_ones",
		"content_version": "1.2.3",
		"difficulty_bands": [{
			"band_id": "intro",
			"generator_id": "addition_v1",
			"generator_parameters": {"maximum": 10},
			"answer_layout": {"id": "numeric_keypad", "options": {}},
			"manipulative": {"id": "counters", "config": {"maximum": 10}, "initial_state": {}},
		}],
	}

func _integer_array(values: Array) -> Array[int]:
	var converted: Array[int] = []
	for value in values:
		converted.append(int(value))
	return converted
