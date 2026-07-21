extends "res://tests/support/test_case.gd"

const ContentContractV1 = preload("res://src/content/generated/content_contract_v1.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")
const NUMBER_VECTOR_PATH := "res://tests/fixtures/contracts/ecmascript_number_vectors.json"
const STRICT_NUMBER_VECTOR_PATH := "res://tests/fixtures/contracts/strict_json_number_vectors.json"
const STRING_VECTOR_PATH := "res://tests/fixtures/contracts/ecmascript_string_vectors.json"
const PUBLISHED_PACKAGE_PATH := "res://tests/content/fixtures/minimal_valid_activity.json"

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
	_test_ecmascript_c0_string_escaping()
	_test_null_character_boundaries_fail_closed()
	_test_ecmascript_unicode_corpus()
	_test_published_package_checksum_regression()
	_test_canonical_json_and_checksum_match_typescript()
	_test_omitted_root_checksum_is_not_preflighted()
	_test_ecmascript_number_to_string_regression()
	_test_ecmascript_number_property_corpus()
	_test_strict_json_boundary_rejects_duplicate_and_unsafe_numbers()
	_test_strict_number_boundary_fixture()
	_test_utf16_source_length_nesting_and_long_string_scanner()
	_test_large_json_scan_has_linear_runtime()
	_test_lone_surrogates_fail_closed()
	_test_object_keys_sort_by_utf16_code_units()

func _test_ecmascript_c0_string_escaping() -> void:
	var validator := ContentValidatorScript.new()
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRING_VECTOR_PATH))
	assert_true(fixture is Dictionary)
	var vectors: Array = fixture["c0"]
	assert_eq(vectors.size(), 0x20)
	for vector_value in vectors:
		var vector: Dictionary = vector_value
		var codepoint: int = vector["codepoint"]
		if codepoint == 0:
			continue
		var character := String.chr(codepoint)
		assert_eq(
			validator.canonical_json({"value": character}),
			vector["value_canonical"],
			"C0 value U+%04x" % codepoint
		)
		var keyed := {}
		keyed["k%s" % character] = 1
		assert_eq(
			validator.canonical_json(keyed),
			vector["key_canonical"],
			"C0 key U+%04x" % codepoint
		)

func _test_null_character_boundaries_fail_closed() -> void:
	var validator := ContentValidatorScript.new()
	for source in ['{"value":"\\u0000"}', '{"key\\u0000":1}']:
		var parsed: Variant = validator.parse_json(source)
		assert_false(parsed.ok)
		assert_eq(parsed.first_error_code(), "INVALID_UNICODE")

	# Godot 4.7 exposes attempted in-memory U+0000 as U+FFFD. The public package
	# validator must reject that lossy representation before checksum comparison.
	var parsed_fixture: Variant = validator.parse_json(
		FileAccess.get_file_as_string(PUBLISHED_PACKAGE_PATH),
		PUBLISHED_PACKAGE_PATH
	)
	assert_true(parsed_fixture.ok)
	var package: Dictionary = parsed_fixture.value.duplicate(true)
	package["localizations"]["ko-KR"]["description"] = String.chr(0xFFFD)
	assert_eq(validator.content_checksum(package), "")
	var validation: Variant = validator.validate_package(package)
	assert_false(validation.ok)
	assert_eq(validation.first_error_code(), "INVALID_UNICODE")
	assert_eq(validation.issues[0]["path"], ["localizations", "ko-KR", "description"])

	var key_package: Dictionary = parsed_fixture.value.duplicate(true)
	var invalid_key := "hidden%skey" % String.chr(0xFFFD)
	key_package["difficulty_bands"][0]["generator_parameters"][invalid_key] = true
	assert_eq(validator.content_checksum(key_package), "")
	var key_validation: Variant = validator.validate_package(key_package)
	assert_false(key_validation.ok)
	assert_eq(key_validation.first_error_code(), "INVALID_UNICODE")
	assert_eq(
		key_validation.issues[0]["path"],
		["difficulty_bands", 0, "generator_parameters", invalid_key]
	)

func _test_ecmascript_unicode_corpus() -> void:
	var validator := ContentValidatorScript.new()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STRING_VECTOR_PATH))
	var metadata: Dictionary = fixture["unicode_corpus"]
	var start: int = metadata["start_codepoint"]
	var count: int = metadata["codepoint_count"]
	var characters := PackedStringArray()
	characters.resize(count)
	for offset in count:
		characters[offset] = String.chr(start + offset)
	var corpus := "".join(characters)
	assert_eq(corpus.length(), 4096)
	assert_eq(
		validator.content_checksum({"value": corpus}),
		metadata["object_checksum"]
	)

func _test_published_package_checksum_regression() -> void:
	var validator := ContentValidatorScript.new()
	var parsed: Variant = validator.parse_json(
		FileAccess.get_file_as_string(PUBLISHED_PACKAGE_PATH),
		PUBLISHED_PACKAGE_PATH
	)
	assert_true(parsed.ok)
	var package: Dictionary = parsed.value
	assert_eq(validator.content_checksum(package), package["checksum"])

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

func _test_omitted_root_checksum_is_not_preflighted() -> void:
	var validator := ContentValidatorScript.new()
	var value := {"value": 1}
	value["checksum"] = value
	assert_eq(validator.canonical_json(value, true), '{"value":1}')
	assert_eq(validator.content_checksum(value), validator.content_checksum({"value": 1}))
	assert_eq(validator.canonical_json(value), "")

func _test_ecmascript_number_to_string_regression() -> void:
	var validator := ContentValidatorScript.new()
	var number := _float_from_hex_bits("3b1d8e556da8dd77")
	assert_eq(
		validator.canonical_json({"n": number}),
		'{"n":6.1120356918828906e-24}'
	)
	assert_eq(
		validator.content_checksum({"n": number}),
		"sha256:499f3763d3ce3f8b86565421bd9d3c1948bac88f3332d4ebb7439fb8bd14de2b"
	)

func _test_ecmascript_number_property_corpus() -> void:
	var validator := ContentValidatorScript.new()
	var vectors: Variant = JSON.parse_string(FileAccess.get_file_as_string(NUMBER_VECTOR_PATH))
	assert_true(vectors is Array)
	assert_eq(vectors.size(), 128)
	for vector_value in vectors:
		var vector: Dictionary = vector_value
		assert_eq(
			validator.canonical_json(_float_from_hex_bits(vector["bits"])),
			vector["canonical"],
			"IEEE-754 bits %s" % vector["bits"]
		)
		var parsed: Variant = validator.parse_json('{"value":%s}' % vector["canonical"])
		assert_true(parsed.ok, "decimal %s issues=%s" % [vector["canonical"], parsed.issues])
		if parsed.ok:
			assert_eq(
				validator.canonical_json(parsed.value),
				'{"value":%s}' % vector["canonical"],
				"decimal %s" % vector["canonical"]
			)

func _float_from_hex_bits(bits: String) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(0, bits.substr(8, 8).hex_to_int())
	bytes.encode_u32(4, bits.substr(0, 8).hex_to_int())
	return bytes.decode_double(0)

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

func _test_strict_number_boundary_fixture() -> void:
	var validator := ContentValidatorScript.new()
	var vectors: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(STRICT_NUMBER_VECTOR_PATH)
	)
	assert_true(vectors is Array)
	for vector_value in vectors:
		var vector: Dictionary = vector_value
		var result: Variant = validator.parse_json('{"value":%s}' % vector["source"])
		if vector.has("error"):
			assert_false(result.ok, vector["source"])
			assert_eq(result.first_error_code(), vector["error"], vector["source"])
			assert_eq(result.issues[0]["path"], ["value"], vector["source"])
		else:
			assert_true(result.ok, "%s issues=%s" % [vector["source"], result.issues])
			var actual_canonical := validator.canonical_json(result.value)
			assert_eq(
				actual_canonical,
				vector["canonical"],
				"%s canonical=%s" % [vector["source"], actual_canonical]
			)

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
	var direct_value := {}
	var cursor: Dictionary = direct_value
	for _depth in 64:
		var child := {}
		cursor["child"] = child
		cursor = child
	assert_false(validator.canonical_json(direct_value).is_empty())
	var too_deep_child := {}
	cursor["child"] = too_deep_child
	assert_eq(validator.canonical_json(direct_value), "")
	assert_eq(validator.content_checksum(direct_value), "")

func _test_large_json_scan_has_linear_runtime() -> void:
	var validator := ContentValidatorScript.new()
	var large_string_source := '"%s"' % "a".repeat(1500000)
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var started_usec := Time.get_ticks_usec()
	var string_result: Variant = validator.parse_json(large_string_source)
	var string_elapsed_usec := Time.get_ticks_usec() - started_usec
	var string_peak_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) - memory_before
	assert_true(string_result.ok)
	assert_true(
		string_elapsed_usec < 3000000,
		"1.5M string scan exceeded 3s: %d usec" % string_elapsed_usec
	)
	assert_true(
		string_peak_bytes < 32 * 1024 * 1024,
		"1.5M string scan peak allocation: %d bytes" % string_peak_bytes
	)

	var number_parts := PackedStringArray()
	number_parts.resize(300000)
	number_parts.fill("0")
	var number_source := "[%s]" % ",".join(number_parts)
	started_usec = Time.get_ticks_usec()
	var number_result: Variant = validator.parse_json(number_source)
	var number_elapsed_usec := Time.get_ticks_usec() - started_usec
	assert_true(number_result.ok)
	assert_true(
		number_elapsed_usec < 3000000,
		"300k number scan exceeded the threshold: %d usec" % number_elapsed_usec
	)

func _test_lone_surrogates_fail_closed() -> void:
	var validator := ContentValidatorScript.new()
	for source in [
		'"\\ud800"',
		'"\\udc00"',
		'{"\\ud800":1}',
	]:
		var result: Variant = validator.parse_json(source)
		assert_false(result.ok)
		assert_eq(result.first_error_code(), "INVALID_JSON")
	for source in ['"�"', '"\\ufffd"', '{"�":1}', '{"\\ufffd":1}']:
		var result: Variant = validator.parse_json(source)
		assert_false(result.ok)
		assert_eq(result.first_error_code(), "INVALID_UNICODE")
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
