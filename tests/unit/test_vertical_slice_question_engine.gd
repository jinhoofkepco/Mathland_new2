extends "res://tests/support/test_case.gd"

const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const VerticalSliceQuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")

const REQUIRED_KEYS := [
	"question_id",
	"activity_id",
	"content_version",
	"generator_id",
	"band_id",
	"seed",
	"resolved_parameters",
	"prompt_key",
	"correct_answer",
	"answer_layout",
	"manipulative",
]

func run(_tree: SceneTree) -> void:
	_test_seeded_generation_is_deterministic()
	_test_invalid_requests_are_rejected()

func _test_seeded_generation_is_deterministic() -> void:
	var repository := VerticalSliceContentRepositoryScript.new()
	var engine := VerticalSliceQuestionEngineScript.new()
	var activity := repository.get_activity(&"foundation_ten_rods")
	var first := engine.generate_question(activity, &"count_to_10", 42)
	var repeated := engine.generate_question(activity, &"count_to_10", 42)
	var next_seed := engine.generate_question(activity, &"count_to_10", 43)
	assert_eq(first, repeated)
	assert_ne(first.get("resolved_parameters", {}), next_seed.get("resolved_parameters", {}))
	for key in REQUIRED_KEYS:
		assert_true(first.has(key), "missing generated question key: %s" % key)
	assert_eq(first.get("activity_id", ""), "foundation_ten_rods")
	assert_eq(first.get("content_version", ""), "a-vertical-1")
	assert_eq(first.get("generator_id", ""), "foundation_ten_rods")
	assert_eq(first.get("band_id", ""), "count_to_10")
	assert_eq(first.get("seed", -1), 42)
	var parameters: Dictionary = first.get("resolved_parameters", {})
	var left: int = parameters.get("left", -1)
	var right: int = parameters.get("right", -1)
	assert_true(left >= 0 and left <= 10)
	assert_true(right >= 0 and right <= 10)
	assert_true(left + right >= 1 and left + right <= 10)
	assert_eq(first.get("correct_answer", null), left + right)
	assert_eq(first.get("answer_layout", ""), "numeric_keypad")
	assert_eq(first.get("manipulative", {}).get("kind", ""), "ten_rods")

func _test_invalid_requests_are_rejected() -> void:
	var engine := VerticalSliceQuestionEngineScript.new()
	assert_eq(engine.generate_question({}, &"count_to_10", 42), {})
	var repository := VerticalSliceContentRepositoryScript.new()
	var activity := repository.get_activity(&"foundation_ten_rods")
	assert_eq(engine.generate_question(activity, &"unknown", 42), {})
	assert_eq(engine.generate_question(activity, &"count_to_10", -1), {})
	assert_eq(engine.generate_question(activity, &"count_to_10", 9007199254740992), {})
	var tampered := activity.duplicate(true)
	tampered["generator_id"] = "arbitrary_script"
	assert_eq(engine.generate_question(tampered, &"count_to_10", 42), {})
