extends "res://tests/support/test_case.gd"

const ExpressionEngineScript = preload("res://src/content/expression/expression_engine.gd")
const EVIDENCE_PATH := "res://tools/content/fixtures/legacy/expected_conversion.json"

func run(_tree: SceneTree) -> void:
	assert_true(FileAccess.file_exists(EVIDENCE_PATH), "Pinned legacy conversion evidence is missing")
	if not FileAccess.file_exists(EVIDENCE_PATH):
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return

	var evidence: Dictionary = parsed
	assert_eq(
		String(evidence.get("source_commit", "")),
		"08b9e7589a335f0c5674cfac6743132f8c4870f2"
	)
	var cases_value: Variant = evidence.get("expression_parity_cases", [])
	assert_true(cases_value is Array)
	if not cases_value is Array:
		return

	var engine := ExpressionEngineScript.new()
	var cases: Array = cases_value
	assert_true(cases.size() >= 5)
	for case_value in cases:
		assert_true(case_value is Dictionary)
		if not case_value is Dictionary:
			continue
		var parity_case: Dictionary = case_value
		var result: Variant = engine.evaluate(
			String(parity_case.get("canonical", "")),
			parity_case.get("variables", {})
		)
		assert_true(result.ok, String(parity_case.get("legacy", "")))
		if result.ok:
			assert_eq(
				int(result.value),
				int(parity_case.get("expected", 0)),
				String(parity_case.get("legacy", ""))
			)
