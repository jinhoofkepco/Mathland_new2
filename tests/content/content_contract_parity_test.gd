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
	assert_eq(ContentContractV1.ACTIVITY_IDS, PackedStringArray(EXPECTED_ACTIVITY_IDS))
	assert_eq(ContentContractV1.GENERATOR_IDS, PackedStringArray(EXPECTED_GENERATOR_IDS))
	assert_eq(ContentContractV1.BAND_IDS, PackedStringArray(["intro", "practice", "challenge"]))
	assert_eq(ContentContractV1.VALIDATION_SEEDS, PackedInt64Array([1, 7, 42, 20260721]))
	assert_eq(ContentContractV1.ACTIVITY_GENERATOR_IDS["addition_ones"], "addition_v1")
	assert_eq(
		ContentContractV1.ACTIVITY_GENERATOR_IDS["foundations_basic_operations"],
		"basic_operations_v1"
	)
	assert_true("checksum" in ContentContractV1.REQUIRED_PACKAGE_KEYS)
	assert_true("packages" in ContentContractV1.REQUIRED_MANIFEST_KEYS)
	_test_canonical_json_and_checksum_match_typescript()
	_test_strict_json_boundary_rejects_duplicate_and_unsafe_numbers()

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
