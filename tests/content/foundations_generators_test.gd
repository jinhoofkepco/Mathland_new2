extends "res://tests/support/test_case.gd"

const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const FIXTURE_PATH := "res://tests/content/fixtures/foundations_generator_cases.json"

const BANDS := {
	"counting_v1": [
		{"count_min":1,"count_max":5},
		{"count_min":1,"count_max":10},
		{"count_min":1,"count_max":20},
	],
	"number_bonds_v1": [
		{"whole_min":2,"whole_max":5,"show_part":"left"},
		{"whole_min":2,"whole_max":10,"show_part":"right"},
		{"whole_min":5,"whole_max":20,"show_part":"random"},
	],
	"ten_frame_v1": [
		{"target_min":0,"target_max":5,"frame_count":1},
		{"target_min":0,"target_max":10,"frame_count":1},
		{"target_min":0,"target_max":20,"frame_count":2},
	],
	"base_ten_v1": [
		{"value_min":10,"value_max":49,"max_place":"tens"},
		{"value_min":10,"value_max":99,"max_place":"tens"},
		{"value_min":100,"value_max":999,"max_place":"hundreds"},
	],
	"number_line_v1": [
		{"axis_min":0,"axis_max":10,"step_min":1,"step_max":3,"direction":"forward"},
		{"axis_min":0,"axis_max":20,"step_min":1,"step_max":5,"direction":"bidirectional"},
		{"axis_min":-10,"axis_max":30,"step_min":1,"step_max":10,"direction":"bidirectional"},
	],
	"basic_operations_v1": [
		{"operators":"addition","operand_min":0,"operand_max":10,"allow_negative":false},
		{"operators":"mixed","operand_min":0,"operand_max":20,"allow_negative":false},
		{"operators":"mixed","operand_min":0,"operand_max":100,"allow_negative":false},
	],
}

func run(_tree: SceneTree) -> void:
	_test_fixed_seed_parity()
	_test_all_band_properties()
	_test_invalid_and_unsafe_inputs_fail_closed()

func _test_fixed_seed_parity() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	for fixture_value in fixtures:
		var fixture: Dictionary = fixture_value
		var generator: Variant = GeneratorRegistryScript.new().create(fixture["generator_id"])
		assert_not_null(generator, fixture["name"])
		var parameters: Dictionary = _normalize_numbers(fixture["parameters"])
		assert_eq(generator.validate_parameters(parameters), PackedStringArray(), fixture["name"])
		assert_eq(
			generator.generate({}, {"generator_parameters":parameters}, int(fixture["seed"])),
			_normalize_numbers(fixture["expected"]),
			fixture["name"]
		)

func _test_all_band_properties() -> void:
	for generator_id in BANDS:
		var generator: Variant = GeneratorRegistryScript.new().create(generator_id)
		for parameters_value in BANDS[generator_id]:
			var parameters: Dictionary = parameters_value
			assert_eq(generator.validate_parameters(parameters), PackedStringArray())
			for seed in range(1, 1001):
				var generated: Dictionary = generator.generate({}, {"generator_parameters":parameters}, seed)
				assert_false(generated.is_empty(), "%s seed %d" % [generator_id, seed])
				if generated.is_empty():
					continue
				var resolved: Dictionary = generated["resolved_parameters"]
				assert_true(_is_flat_serializable(resolved))
				var answer: int = generated["correct_answer"]["value"]
				if generator_id == "counting_v1":
					assert_eq(resolved["manipulative_id"], "counters")
					assert_eq(resolved["item_ids"], _indices(resolved["count"]))
					assert_eq(resolved["initial_occupied"], resolved["item_ids"])
					assert_eq(answer, resolved["count"])
				elif generator_id == "number_bonds_v1":
					assert_eq(resolved["manipulative_id"], "counters")
					assert_eq(resolved["parts"][0] + resolved["parts"][1], resolved["whole"])
					assert_eq(resolved["initial_occupied"].size(), resolved["shown_part"])
					assert_eq(answer, resolved["missing_part"])
				elif generator_id == "ten_frame_v1":
					assert_eq(resolved["manipulative_id"], "ten_frame")
					assert_eq(resolved["occupied_cells"], _indices(resolved["target"]))
					assert_true(resolved["occupied_cells"].size() <= resolved["frame_count"] * 10)
					assert_eq(answer, resolved["target"])
				elif generator_id == "base_ten_v1":
					assert_eq(resolved["manipulative_id"], "base_ten")
					assert_eq(
						resolved["hundreds"] * 100 + resolved["tens"] * 10 + resolved["ones"],
						resolved["value"]
					)
					assert_eq(resolved["place_counts"], [resolved["hundreds"],resolved["tens"],resolved["ones"]])
					assert_eq(answer, resolved["value"])
				elif generator_id == "number_line_v1":
					assert_eq(resolved["manipulative_id"], "number_line")
					var sum := 0
					for step in resolved["signed_steps"]:
						sum += step
					assert_eq(resolved["start"] + sum, resolved["endpoint"])
					assert_true(resolved["endpoint"] >= resolved["axis_min"])
					assert_true(resolved["endpoint"] <= resolved["axis_max"])
					assert_eq(resolved["visited_ticks"], [resolved["start"]])
					assert_eq(answer, resolved["endpoint"])
				else:
					assert_eq(resolved["manipulative_id"], "counters")
					var recomputed: int = (
						resolved["operands"][0] + resolved["operands"][1]
						if resolved["operator"] == "+"
						else resolved["operands"][0] - resolved["operands"][1]
					)
					assert_eq(recomputed, resolved["answer"])
					assert_true(recomputed >= 0 and recomputed <= parameters["operand_max"])
					assert_eq(resolved["initial_counts"], resolved["operands"])
					assert_eq(answer, recomputed)

func _test_invalid_and_unsafe_inputs_fail_closed() -> void:
	var invalid_cases := {
		"counting_v1":{"count_min":0,"count_max":129},
		"number_bonds_v1":{"whole_min":2,"whole_max":129,"show_part":"middle"},
		"ten_frame_v1":{"target_min":0,"target_max":11,"frame_count":1},
		"base_ten_v1":{"value_min":10,"value_max":100,"max_place":"tens"},
		"number_line_v1":{"axis_min":0,"axis_max":128,"step_min":1,"step_max":129,"direction":"sideways"},
		"basic_operations_v1":{"operators":"addition","operand_min":6,"operand_max":10,"allow_negative":true},
	}
	for generator_id in invalid_cases:
		var generator: Variant = GeneratorRegistryScript.new().create(generator_id)
		var parameters: Dictionary = invalid_cases[generator_id]
		assert_false(generator.validate_parameters(parameters).is_empty())
		assert_eq(generator.generate({}, {"generator_parameters":parameters}, 1), {})
		assert_eq(generator.last_error, "INVALID_PARAMETERS")
		assert_eq(generator.generate({}, {"generator_parameters":BANDS[generator_id][0]}, 0x100000000), {})
		assert_eq(generator.last_error, "INVALID_SEED")

func _is_flat_serializable(parameters: Dictionary) -> bool:
	for value in parameters.values():
		if value is bool or typeof(value) == TYPE_INT or value is String:
			continue
		if value is Array and value.size() <= 128:
			for element in value:
				if typeof(element) != TYPE_INT:
					return false
			continue
		return false
	return true

func _indices(count: int) -> Array[int]:
	var values: Array[int] = []
	for index in count:
		values.append(index)
	return values

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
