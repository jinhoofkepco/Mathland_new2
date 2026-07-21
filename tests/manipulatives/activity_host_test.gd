extends "res://tests/support/test_case.gd"

const ActivityRunScene = preload("res://scenes/game/activity_run.tscn")
const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const RunConfigScript = preload("res://src/game/run_config.gd")
const RunControllerScript = preload("res://src/game/run_controller.gd")

class FakeRepository extends RefCounted:
	var activity: Dictionary
	func _init(value: Dictionary) -> void:
		activity = value.duplicate(true)
	func get_activity(_activity_id: StringName, _version := "") -> Dictionary:
		return activity.duplicate(true)

class FixedQuestionEngine extends RefCounted:
	var question: Dictionary
	func _init(value: Dictionary) -> void:
		question = value.duplicate(true)
	func generate_question(_activity: Dictionary, _band_id: StringName, seed: int) -> Dictionary:
		var result := question.duplicate(true)
		result["seed"] = seed
		return result

class RecordingSession extends RefCounted:
	signal answer_committed(event: Dictionary, transition: RefCounted)
	signal run_completed(event: Dictionary, state: Dictionary)
	signal persistence_failed(code: String)
	var starts := 0
	var submissions: Array[Variant] = []
	var state := {"status": "running", "awaiting_answer": true, "health": 3, "score": 0}
	func start_run(_activity: Dictionary, _question: Dictionary) -> Dictionary:
		starts += 1
		return {"ok": true, "state": state.duplicate(true)}
	func submit_answer(answer: Variant, _response_ms: int, _hints := 0) -> Dictionary:
		submissions.append(answer.duplicate(true) if answer is Dictionary or answer is Array else answer)
		return {"ok": true, "state": state.duplicate(true)}
	func snapshot() -> Dictionary:
		return state.duplicate(true)
	func session_id() -> String:
		return "test-session"
	func is_blocked() -> bool:
		return false

func run(tree: SceneTree) -> void:
	_test_v1_run_contract()
	await _test_all_activities_use_one_host_path(tree)
	await _test_unknown_factory_ids_fail_before_start(tree)

func _test_v1_run_contract() -> void:
	var activity := _activity("addition_ones", "numeric_keypad", "none")
	var config: RefCounted = RunConfigScript.from_activity(activity)
	assert_true(config.is_valid())
	assert_eq(config.initial_health, 3)
	assert_eq(config.target_score, 4)
	assert_eq(config.reward_per_correct, {"apples": 2})
	assert_eq(config.reward_on_completion, {"apples": 5})
	assert_eq(config.combo_thresholds, [2, 4, 7])
	var controller := RunControllerScript.new()
	assert_true(controller.start(config, "v1-session").ok)
	assert_true(controller.begin_question(_question("addition_ones", "numeric_keypad", "none", {"kind": "integer", "value": 7})).ok)
	var malformed_question := _question("addition_ones", "numeric_keypad", "none", {"kind": "integer", "value": 7})
	malformed_question.prompt.args = {"nested": {"unsafe": true}}
	var malformed_controller := RunControllerScript.new()
	assert_true(malformed_controller.start(config, "v1-malformed").ok)
	assert_false(malformed_controller.begin_question(malformed_question).ok)
	var terminal_activity := activity.duplicate(true)
	terminal_activity.run.goal.target = 1
	var terminal_controller := RunControllerScript.new()
	assert_true(terminal_controller.start(RunConfigScript.from_activity(terminal_activity), "v1-terminal").ok)
	assert_true(terminal_controller.begin_question(_question("addition_ones", "numeric_keypad", "none", {"kind": "integer", "value": 7})).ok)
	var transition: RefCounted = terminal_controller.plan_answer({"kind": "integer", "value": 7}, 20, 0)
	assert_not_null(transition)
	assert_eq(transition.reward_delta, {"apples": 7})
	assert_eq(transition.next_state.earned_rewards, {"apples": 7})
	assert_true("reward" in transition.effect_names)

func _test_all_activities_use_one_host_path(tree: SceneTree) -> void:
	for index in Contract.ACTIVITY_IDS.size():
		var activity_id: String = Contract.ACTIVITY_IDS[index]
		var layout_id := "factor_slots" if activity_id == "prime_factorization" else "numeric_keypad"
		var answer := {"kind": "integer_list", "values": [2, 2, 3], "order_matters": false} if layout_id == "factor_slots" else {"kind": "integer", "value": index + 1}
		var session := RecordingSession.new()
		var screen: Control = ActivityRunScene.instantiate()
		screen.configure({
			"activity_id": activity_id,
			"content_repository": FakeRepository.new(_activity(activity_id, layout_id, "none")),
			"question_engine": FixedQuestionEngine.new(_question(activity_id, layout_id, "none", answer)),
			"run_session": session,
		})
		tree.root.add_child(screen)
		await tree.process_frame
		assert_eq(session.starts, 1, activity_id)
		screen.skip_introduction()
		var answer_input: Control = screen.find_child("AnswerInput", true, false)
		assert_not_null(answer_input, activity_id)
		if answer_input != null:
			if layout_id == "factor_slots":
				answer_input.set_values(answer.values)
			else:
				answer_input.set_integer(answer.value)
			answer_input.submit_current_answer()
			assert_eq(session.submissions, [answer], activity_id)
		screen.queue_free()
		await tree.process_frame

func _test_unknown_factory_ids_fail_before_start(tree: SceneTree) -> void:
	for invalid in [{"layout": "unknown", "manipulative": "none"}, {"layout": "numeric_keypad", "manipulative": "unknown"}]:
		var session := RecordingSession.new()
		var screen: Control = ActivityRunScene.instantiate()
		var activity := _activity("addition_ones", invalid.layout, invalid.manipulative)
		screen.configure({
			"activity_id": "addition_ones",
			"content_repository": FakeRepository.new(activity),
			"question_engine": FixedQuestionEngine.new(_question("addition_ones", invalid.layout, invalid.manipulative, {"kind": "integer", "value": 1})),
			"run_session": session,
		})
		tree.root.add_child(screen)
		await tree.process_frame
		assert_eq(session.starts, 0)
		screen.queue_free()
		await tree.process_frame

func _activity(activity_id: String, layout_id: String, manipulative_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"activity_id": activity_id,
		"content_version": "1.0.0",
		"localizations": {"ko-KR": {"title": "Test", "description": "Test", "tutorial_steps": ["Test"]}},
		"run": {
			"starting_hearts": 3,
			"goal": {"kind": "correct_answers", "target": 4},
			"timer": {"enabled": false, "seconds": 0, "profile_can_disable": true},
			"rewards": {"apples_per_correct": 2, "completion_apples": 5},
			"combo_thresholds": [2, 4, 7],
			"boss_every_correct": 2,
			"effects": {
				"correct": "correct", "wrong": "wrong", "combo": "combo_1",
				"boss": "boss", "level_up": "level_up", "reward": "reward",
				"health_loss": "health_loss",
			},
		},
		"difficulty_bands": [{
			"band_id": "intro",
			"generator_id": "addition_v1",
			"generator_parameters": {},
			"answer_layout": {"id": layout_id},
			"manipulative": {"id": manipulative_id, "config": {}, "initial_state": {}},
		}],
		"adaptive_policy": {"enabled_by_default": false},
	}

func _question(activity_id: String, layout_id: String, manipulative_id: String, answer: Dictionary) -> Dictionary:
	var options := {"allowed_values": [2, 3, 5], "slot_count": 6} if layout_id == "factor_slots" else {}
	return {
		"contract_version": 1,
		"activity_id": activity_id,
		"content_version": "1.0.0",
		"generator_id": "addition_v1",
		"band_id": "intro",
		"seed": 42,
		"resolved_parameters": {},
		"prompt": {"key": "question.test", "args": {}},
		"correct_answer": answer.duplicate(true),
		"answer_layout": {"id": layout_id, "options": options} if not options.is_empty() else {"id": layout_id},
		"manipulative": {"id": manipulative_id, "config": {}, "initial_state": {}},
	}
