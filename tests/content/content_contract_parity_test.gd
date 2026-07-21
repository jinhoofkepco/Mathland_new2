extends "res://tests/support/test_case.gd"

const ContentContractV1 = preload("res://src/content/generated/content_contract_v1.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")

const EXPECTED_ACTIVITY_IDS := [
	"addition_ones",
	"subtraction_ones",
	"multiplication",
	"common_multiples_lcm",
	"prime_factorization",
	"foundations_counting",
	"foundations_number_bonds",
	"foundations_ten_frame",
	"foundations_base_ten",
	"foundations_number_line",
	"foundations_basic_operations",
]
const EXPECTED_GENERATOR_IDS := [
	"addition_v1",
	"subtraction_v1",
	"multiplication_v1",
	"common_multiple_v1",
	"prime_factorization_v1",
	"counting_v1",
	"number_bonds_v1",
	"ten_frame_v1",
	"base_ten_v1",
	"number_line_v1",
	"basic_operations_v1",
]

func run(_tree: SceneTree) -> void:
	assert_eq(ContentContractV1.SCHEMA_VERSION, 1)
	assert_eq(ContentContractV1.SAFE_INTEGER_MIN, -9007199254740991)
	assert_eq(ContentContractV1.SAFE_INTEGER_MAX, 9007199254740991)
	assert_eq(ContentContractV1.CHECKSUM_PREFIX, "sha256:")
	assert_eq(ContentContractV1.CHECKSUM_HEX_LENGTH, 64)
	assert_eq(ContentContractV1.ACTIVITY_IDS, EXPECTED_ACTIVITY_IDS)
	assert_eq(ContentContractV1.GENERATOR_IDS, EXPECTED_GENERATOR_IDS)
	assert_eq(ContentContractV1.BAND_IDS, ["intro", "practice", "challenge"])
	assert_eq(ContentContractV1.VALIDATION_SEEDS, [1, 7, 42, 20260721])
	assert_eq(ContentContractV1.ACTIVITY_GENERATOR_IDS["addition_ones"], "addition_v1")
	assert_eq(
		ContentContractV1.ACTIVITY_GENERATOR_IDS["foundations_basic_operations"],
		"basic_operations_v1"
	)
	assert_true("checksum" in ContentContractV1.REQUIRED_PACKAGE_KEYS)
	assert_true("packages" in ContentContractV1.REQUIRED_MANIFEST_KEYS)
	_test_canonical_json_and_checksum_match_typescript()
	_test_strict_json_boundary_rejects_duplicate_and_unsafe_numbers()
	_test_utf16_source_length_nesting_and_long_string_scanner()
	_test_lone_surrogates_fail_closed()
	_test_object_keys_sort_by_utf16_code_units()

func _test_canonical_json_and_checksum_match_typescript() -> void:
	var validator := ContentValidatorScript.new()
	var value := {
		"z": [2, 1],
		"nested": {"y": 2, "checksum": "keep", "x": 1},
		"checksum": "ignored",
		"title": "수학 섬",
	}
	assert_eq(
		validator.canonical_json(value, true),
		'{"nested":{"checksum":"keep","x":1,"y":2},"title":"수학 섬","z":[2,1]}'
	)
	assert_eq(
		validator.content_checksum(value),
		"sha256:03665022ea57b10b402beb9a93b15e1789ee1c553a3278141973bbcc7e94a8af"
	)
	assert_eq(validator.canonical_json({"n": 0.8}), '{"n":0.8}')
	assert_eq(validator.canonical_json({"n": 0.000001}), '{"n":0.000001}')
	assert_eq(validator.canonical_json({"n": 0.0000001}), '{"n":1e-7}')
	assert_eq(validator.canonical_json({"n": 0.00000012}), '{"n":1.2e-7}')
	assert_eq(
		validator.canonical_json({"n": 1.2345678901234567}),
		'{"n":1.2345678901234567}'
	)
	assert_eq(
		validator.canonical_json({"n": 0.9876543210987654}),
		'{"n":0.9876543210987654}'
	)
	assert_eq(
		validator.canonical_json({"n": 1.234567890123456e-7}),
		'{"n":1.234567890123456e-7}'
	)
	assert_eq(validator.canonical_json({"n": 9007199254740992.0}), "")

func _test_strict_json_boundary_rejects_duplicate_and_unsafe_numbers() -> void:
	var validator := ContentValidatorScript.new()
	var duplicate: Variant = validator.parse_json('{"nested":{"seed":1,"s\\u0065ed":7}}')
	assert_false(duplicate.ok)
	assert_eq(duplicate.first_error_code(), "DUPLICATE_KEY")
	var unsafe_integer: Variant = validator.parse_json('{"seed":9007199254740992}')
	assert_false(unsafe_integer.ok)
	assert_eq(unsafe_integer.first_error_code(), "UNSAFE_INTEGER")
	assert_false(validator.parse_json('{"a":01}').ok)
	assert_true(validator.parse_json('{"a":[true,null,-1.25e2],"한글":"값"}').ok)

func _test_utf16_source_length_nesting_and_long_string_scanner() -> void:
	var validator := ContentValidatorScript.new()
	assert_eq(validator._utf16_length("A😀"), 3)
	assert_true(validator.parse_json("%s0%s" % ["[".repeat(64), "]".repeat(64)]).ok)
	var too_deep: Variant = validator.parse_json(
		"%s0%s" % ["[".repeat(65), "]".repeat(65)]
	)
	assert_false(too_deep.ok)
	assert_eq(too_deep.first_error_code(), "NESTING_TOO_DEEP")
	var long_value := "가".repeat(100000)
	var parsed: Variant = validator.parse_json(JSON.stringify(long_value))
	assert_true(parsed.ok)
	assert_eq(parsed.value, long_value)

func _test_lone_surrogates_fail_closed() -> void:
	var validator := ContentValidatorScript.new()
	for source in ['"\\ud800"', '"\\udc00"', '{"\\ud800":1}']:
		var result: Variant = validator.parse_json(source)
		assert_false(result.ok)
		assert_eq(result.first_error_code(), "INVALID_JSON")
	assert_eq(validator.parse_json('"\\ud83d\\ude00"').value, "😀")
	# Godot replaces an in-memory lone surrogate with U+FFFD before validation.
	var lone_surrogate_replacement := String.chr(0xFFFD)
	assert_eq(validator.canonical_json({"value": lone_surrogate_replacement}), "")
	var lone_key := {}
	lone_key[lone_surrogate_replacement] = 1
	assert_eq(validator.canonical_json(lone_key), "")

func _test_object_keys_sort_by_utf16_code_units() -> void:
	var validator := ContentValidatorScript.new()
	var astral := String.chr(0x10000)
	var private_use_bmp := String.chr(0xE000)
	var value := {}
	value[private_use_bmp] = 2
	value[astral] = 1
	assert_eq(
		validator.canonical_json(value),
		"{%s:1,%s:2}" % [JSON.stringify(astral), JSON.stringify(private_use_bmp)]
	)
