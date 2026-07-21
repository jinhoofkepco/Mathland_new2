extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const ManipulativeScript = preload("res://src/game/manipulatives/manipulative.gd")

class TestManipulative extends ManipulativeScript:
	var configured := false
	var current_state := {}

	func configure(config: Dictionary, question: Dictionary) -> void:
		configured = not config.is_empty() and not question.is_empty()

	func reset_state() -> void:
		current_state = {}

	func get_answer_state() -> Dictionary:
		return current_state.duplicate(true)

	func apply_answer_state(state: Dictionary) -> void:
		current_state = state.duplicate(true)
		state_changed.emit(get_answer_state())

func run(_tree: SceneTree) -> void:
	_test_base_contracts_are_safe()
	_test_repository_returns_isolated_data()
	_test_manipulative_contract()

func _test_base_contracts_are_safe() -> void:
	var repository := ContentRepositoryScript.new()
	assert_eq(repository.get_activity(&"missing"), {})
	assert_eq(repository.list_activities(), [])
	assert_eq(repository.get_active_version(&"missing"), "")
	assert_eq(repository.get_manifest_version(), "")
	var engine := QuestionEngineScript.new()
	assert_eq(engine.generate_question({}, &"missing", 1), {})

func _test_repository_returns_isolated_data() -> void:
	var repository := VerticalSliceContentRepositoryScript.new()
	assert_eq(repository.get_manifest_version(), "a-vertical-manifest-1")
	assert_eq(repository.get_active_version(&"foundation_ten_rods"), "a-vertical-1")
	assert_eq(repository.get_active_version(&"unknown"), "")
	var activity := repository.get_activity(&"foundation_ten_rods")
	assert_eq(activity.get("activity_id", ""), "foundation_ten_rods")
	assert_eq(activity.get("content_version", ""), "a-vertical-1")
	assert_eq(activity.get("initial_health", 0), 3)
	assert_eq(activity.get("target_score", 0), 5)
	assert_false(activity.get("timer", {}).get("enabled", true))
	assert_eq(activity.get("reward_per_correct", {}).get("apples", 0), 2)
	assert_eq(activity.get("bands", [])[0].get("band_id", ""), "count_to_10")
	assert_eq(
		activity.get("manipulative", {}).get("scene_path", ""),
		"res://scenes/game/manipulatives/ten_rod_board.tscn"
	)
	activity["target_score"] = 999
	activity["bands"][0]["maximum"] = 999
	var reread := repository.get_activity(&"foundation_ten_rods")
	assert_eq(reread.get("target_score", 0), 5)
	assert_eq(reread.get("bands", [])[0].get("maximum", 0), 10)
	var listed := repository.list_activities()
	assert_eq(listed.size(), 1)
	listed[0]["content_version"] = "mutated"
	assert_eq(repository.list_activities()[0].get("content_version", ""), "a-vertical-1")
	assert_eq(repository.get_activity(&"foundation_ten_rods", "missing"), {})

func _test_manipulative_contract() -> void:
	var manipulative := TestManipulative.new()
	manipulative.configure({"kind": "ten_rods"}, {"question_id": "q-1"})
	assert_true(manipulative.configured)
	manipulative.set_interaction_enabled(false)
	assert_eq(manipulative.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	manipulative.set_interaction_enabled(true)
	assert_eq(manipulative.mouse_filter, Control.MOUSE_FILTER_STOP)
	manipulative.apply_answer_state({"value": 7})
	var returned := manipulative.get_answer_state()
	returned["value"] = 99
	assert_eq(manipulative.get_answer_state(), {"value": 7})
	manipulative.reset_state()
	assert_eq(manipulative.get_answer_state(), {})
	manipulative.free()
