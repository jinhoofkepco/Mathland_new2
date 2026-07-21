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

class StaticGenerator extends QuestionGeneratorScript:
	var output: Dictionary

	func _init(generated_output: Dictionary) -> void:
		output = generated_output.duplicate(true)

	func validate_parameters(_parameters: Dictionary) -> PackedStringArray:
		return PackedStringArray()

	func generate(_activity: Dictionary, _band: Dictionary, _seed: int) -> Dictionary:
		return output.duplicate(true)

class StaticRegistry extends GeneratorRegistryScript:
	var output: Dictionary

	func _init(generated_output: Dictionary) -> void:
		output = generated_output.duplicate(true)

	func create(generator_id: String) -> Variant:
		return StaticGenerator.new(output) if generator_id == "addition_v1" else null

class FailingGenerator extends QuestionGeneratorScript:
	func validate_parameters(_parameters: Dictionary) -> PackedStringArray:
		return PackedStringArray()

	func generate(_activity: Dictionary, _band: Dictionary, _seed: int) -> Dictionary:
		last_error = "UNSATISFIABLE_PARAMETERS"
		return {}

class FailingRegistry extends GeneratorRegistryScript:
	func create(generator_id: String) -> Variant:
		return FailingGenerator.new() if generator_id == "addition_v1" else null

func run(_tree: SceneTree) -> void:
	_test_rng_vector_and_helpers()
	_test_registry_allowlist()
	_test_question_envelope_is_deterministic_and_isolated()
	_test_question_engine_rejects_unknown_or_ambiguous_content()
	_test_question_engine_validates_generated_safe_domain()
	_test_question_engine_preserves_generator_diagnostic()

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
	assert_eq(rng.range_int(5, 2), -1)
	assert_false(SeededRngScript.new(-1).is_valid)
	assert_false(SeededRngScript.new(0x100000000).is_valid)
	assert_true(SeededRngScript.new(0xFFFFFFFF).is_valid)
	assert_eq(SeededRngScript.new(1).range_int(0, 0x100000000), -1)

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
	assert_eq(engine.generate_question(_activity(), &"intro", 0x100000000), {})
	assert_eq(engine.last_diagnostic, "INVALID_SEED")

func _test_question_engine_validates_generated_safe_domain() -> void:
	var valid := {
		"resolved_parameters": {"draw": 1, "operands": [4, 3], "carry": false},
		"prompt": {"key": "activity.addition.prompt", "args": {"left": 4, "right": 3}},
		"correct_answer": {"kind": "integer", "value": 7},
	}
	var invalid_outputs: Array[Dictionary] = []
	var extra := valid.duplicate(true)
	extra["remote_metadata"] = "untrusted"
	invalid_outputs.append(extra)
	var nested_parameters := valid.duplicate(true)
	nested_parameters["resolved_parameters"]["nested"] = {"unsafe": true}
	invalid_outputs.append(nested_parameters)
	var unsafe_parameter := valid.duplicate(true)
	unsafe_parameter["resolved_parameters"]["draw"] = 9007199254740992
	invalid_outputs.append(unsafe_parameter)
	var bad_prompt := valid.duplicate(true)
	bad_prompt["prompt"]["args"]["left"] = true
	invalid_outputs.append(bad_prompt)
	var malformed_prompt := valid.duplicate(true)
	malformed_prompt["prompt"]["remote"] = "untrusted"
	invalid_outputs.append(malformed_prompt)
	var bad_answer := valid.duplicate(true)
	bad_answer["correct_answer"]["value"] = 9007199254740992
	invalid_outputs.append(bad_answer)
	var malformed_answer := valid.duplicate(true)
	malformed_answer["correct_answer"] = {
		"kind":"integer_list","values":[2,2],
	}
	invalid_outputs.append(malformed_answer)
	for output in invalid_outputs:
		var engine := QuestionEngineScript.new(StaticRegistry.new(output))
		assert_eq(engine.generate_question(_activity(), &"intro", 1), {})
		assert_eq(engine.last_diagnostic, "INVALID_GENERATOR_OUTPUT")

	var invalid_layout := _activity()
	invalid_layout["difficulty_bands"][0]["answer_layout"] = {"id":"remote_layout"}
	var layout_engine := QuestionEngineScript.new(StaticRegistry.new(valid))
	assert_eq(layout_engine.generate_question(invalid_layout, &"intro", 1), {})
	assert_eq(layout_engine.last_diagnostic, "INVALID_BAND")
	var invalid_manipulative := _activity()
	invalid_manipulative["difficulty_bands"][0]["manipulative"]["config"]["nested"] = {}
	assert_eq(layout_engine.generate_question(invalid_manipulative, &"intro", 1), {})
	assert_eq(layout_engine.last_diagnostic, "INVALID_BAND")
	var invalid_activity := _activity()
	invalid_activity["activity_id"] = "../remote"
	assert_eq(layout_engine.generate_question(invalid_activity, &"intro", 1), {})
	assert_eq(layout_engine.last_diagnostic, "INVALID_ACTIVITY")
	var oversized_version := _activity()
	oversized_version["content_version"] = "1.%s.0" % "1".repeat(200)
	assert_eq(layout_engine.generate_question(oversized_version, &"intro", 1), {})
	assert_eq(layout_engine.last_diagnostic, "INVALID_ACTIVITY")

func _test_question_engine_preserves_generator_diagnostic() -> void:
	var engine := QuestionEngineScript.new(FailingRegistry.new())
	assert_eq(engine.generate_question(_activity(), &"intro", 7), {})
	assert_eq(engine.last_diagnostic, "GENERATOR_FAILED")
	assert_eq(engine.last_diagnostic_detail, {
		"code": "GENERATOR_FAILED",
		"generator_id": "addition_v1",
		"generator_error": "UNSATISFIABLE_PARAMETERS",
	})

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
