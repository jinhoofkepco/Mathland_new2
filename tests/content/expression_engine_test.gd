extends "res://tests/support/test_case.gd"

const ExpressionEngineScript = preload("res://src/content/expression/expression_engine.gd")
const FIXTURE_PATH := "res://tests/content/fixtures/expression_cases.json"

func run(_tree: SceneTree) -> void:
	var engine := ExpressionEngineScript.new()
	var fixtures: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	assert_true(fixtures is Array)
	for fixture_value in fixtures:
		var fixture: Dictionary = fixture_value
		var result: Variant = engine.evaluate(fixture["source"], fixture["variables"])
		assert_eq(result.ok, fixture["ok"], fixture["name"])
		assert_eq(result.value, int(fixture["value"]), fixture["name"])
		assert_eq(result.error_code, fixture["error_code"], fixture["name"])
		assert_eq(result.offset, int(fixture["offset"]), fixture["name"])

	_test_source_limit_uses_utf16_code_units(engine)
	_test_invalid_variables_fail_closed(engine)

func _test_source_limit_uses_utf16_code_units(engine: Variant) -> void:
	var too_long: Variant = engine.evaluate("1".repeat(513))
	assert_false(too_long.ok)
	assert_eq(too_long.error_code, "TOO_COMPLEX")
	assert_eq(too_long.offset, 512)
	var astral_boundary: Variant = engine.evaluate(" ".repeat(511) + "😀")
	assert_false(astral_boundary.ok)
	assert_eq(astral_boundary.error_code, "TOO_COMPLEX")
	assert_eq(astral_boundary.offset, 512)

func _test_invalid_variables_fail_closed(engine: Variant) -> void:
	var fractional: Variant = engine.evaluate("A", {"A": 1.5})
	assert_false(fractional.ok)
	assert_eq(fractional.error_code, "OVERFLOW")
	assert_eq(fractional.offset, 0)
	var wrong_type: Variant = engine.evaluate("A", {"A": "1"})
	assert_false(wrong_type.ok)
	assert_eq(wrong_type.error_code, "OVERFLOW")
	assert_eq(wrong_type.offset, 0)
