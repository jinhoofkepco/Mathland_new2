extends "res://tests/support/test_case.gd"

const FakeClockScript = preload("res://tests/support/fake_clock.gd")
const RunConfigScript = preload("res://src/game/run_config.gd")
const RunControllerScript = preload("res://src/game/run_controller.gd")
const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")

func run(_tree: SceneTree) -> void:
	_test_correct_boss_target_and_preview_commit()
	_test_wrong_answers_deplete_health_without_losing_rewards()
	_test_stale_transition_and_canonical_answers()
	_test_disabled_and_paused_timers()
	_test_question_cannot_be_skipped_or_rewarded_twice()
	_test_config_is_derived_without_mutating_activity()
	_test_invalid_config_and_question_are_contained()

func _test_correct_boss_target_and_preview_commit() -> void:
	var clock := FakeClockScript.new(1000)
	var controller := RunControllerScript.new(clock)
	var config := _config({"target_score": 2, "boss_question_indices": [1]})
	assert_true(controller.start(config, "session-a").ok)
	assert_true(controller.begin_question(_question(42, 7)).ok)
	var before := controller.snapshot()
	var first = controller.plan_answer(7, 1200, 0)
	assert_not_null(first)
	assert_eq(controller.snapshot(), before, "planning must not mutate current state")
	assert_true(first.correctness)
	assert_eq(first.health_delta, 0)
	assert_eq(first.reward_delta, {"apples": 2})
	assert_eq(first.next_state.health, 3)
	assert_eq(first.next_state.score, 1)
	assert_eq(first.next_state.combo, 1)
	assert_eq(first.next_state.earned_rewards, {"apples": 2})
	assert_eq(first.effect_name, "correct")
	assert_true(controller.commit(first).ok)
	assert_eq(controller.snapshot().revision, before.revision + 1)

	assert_true(controller.begin_question(_question(43, 8)).ok)
	var boss = controller.plan_answer(8, 900, 0)
	assert_not_null(boss)
	assert_true(boss.next_state.boss_state)
	assert_eq(boss.effect_name, "boss")
	assert_eq(boss.follow_up_effect_name, "level_up")
	assert_eq(boss.effect_intensity, 1.0)
	assert_true("target_reached" in boss.effect_names)
	assert_true("level_up" in boss.effect_names)
	assert_eq(boss.next_state.completion_reason, "target_reached")
	assert_eq(boss.next_state.status, "completed")
	assert_eq(boss.next_state.earned_rewards, {"apples": 4})
	assert_true(controller.commit(boss).ok)
	assert_eq(controller.snapshot().completion_reason, "target_reached")

func _test_wrong_answers_deplete_health_without_losing_rewards() -> void:
	var controller := RunControllerScript.new(FakeClockScript.new())
	assert_true(controller.start(_config({"target_score": 99}), "session-health").ok)
	assert_true(controller.begin_question(_question(1, 3)).ok)
	var earned = controller.plan_answer(3, 100, 0)
	assert_true(controller.commit(earned).ok)
	for index in 3:
		assert_true(controller.begin_question(_question(10 + index, 4)).ok)
		var wrong = controller.plan_answer(9, 200, 1)
		assert_false(wrong.correctness)
		assert_eq(wrong.health_delta, -1)
		assert_eq(wrong.reward_delta, {})
		assert_eq(wrong.next_state.combo, 0)
		assert_true("wrong" in wrong.effect_names)
		assert_true("health_loss" in wrong.effect_names)
		assert_true(controller.commit(wrong).ok)
	var state := controller.snapshot()
	assert_eq(state.health, 0)
	assert_eq(state.status, "completed")
	assert_eq(state.completion_reason, "health_depleted")
	assert_eq(state.earned_rewards, {"apples": 2}, "health depletion must preserve earned rewards")

func _test_stale_transition_and_canonical_answers() -> void:
	var controller := RunControllerScript.new(FakeClockScript.new())
	assert_true(controller.start(_config({"target_score": 10, "combo_thresholds": [2, 3]}), "session-stale").ok)
	assert_true(controller.begin_question(_question(1, {"kind": "integer_list", "values": [2, 3], "order_matters": false})).ok)
	var first = controller.plan_answer({"kind": "integer_list", "values": [3, 2], "order_matters": false}, 10, 0)
	var stale = controller.plan_answer({"kind": "integer_list", "values": [2, 3], "order_matters": false}, 10, 0)
	assert_true(first.correctness)
	assert_true(controller.commit(first).ok)
	var stale_result := controller.commit(stale)
	assert_false(stale_result.ok)
	assert_eq(stale_result.error, "stale_transition")
	assert_true(controller.begin_question(_question(2, 5)).ok)
	var combo = controller.plan_answer(5, 10, 0)
	assert_eq(combo.effect_name, "combo_1")

func _test_disabled_and_paused_timers() -> void:
	var disabled_clock := FakeClockScript.new()
	var disabled := RunControllerScript.new(disabled_clock)
	assert_true(disabled.start(_config({"timer_allowed": false, "timer_duration_ms": 0}), "session-no-timer").ok)
	assert_true(disabled.begin_question(_question(1, 1)).ok)
	disabled_clock.advance_ms(60000)
	assert_eq(disabled.time_remaining_ms(), 0)
	assert_null(disabled.plan_timeout())

	var clock := FakeClockScript.new()
	var controller := RunControllerScript.new(clock)
	assert_true(controller.start(_config({"timer_allowed": true, "timer_duration_ms": 5000}), "session-timer").ok)
	assert_true(controller.begin_question(_question(2, 2)).ok)
	clock.advance_ms(2000)
	assert_eq(controller.time_remaining_ms(), 3000)
	assert_true(controller.pause())
	clock.advance_ms(10000)
	assert_eq(controller.time_remaining_ms(), 3000)
	assert_null(controller.plan_timeout())
	assert_true(controller.resume())
	assert_eq(controller.time_remaining_ms(), 3000)
	clock.advance_ms(2999)
	assert_null(controller.plan_timeout())
	clock.advance_ms(1)
	assert_null(controller.plan_answer(2, 5000, 0), "an answer cannot beat an already expired timer")
	var timeout = controller.plan_timeout()
	assert_not_null(timeout)
	assert_eq(timeout.kind, "timeout")
	assert_eq(timeout.health_delta, -1)

func _test_config_is_derived_without_mutating_activity() -> void:
	var activity := VerticalSliceContentRepositoryScript.new().get_activity(&"foundation_ten_rods")
	var before := activity.duplicate(true)
	var config = RunConfigScript.from_activity(activity)
	assert_true(config.is_valid())
	assert_eq(config.stage_id, "count_to_10")
	assert_eq(config.initial_health, 3)
	assert_eq(config.target_score, 5)
	assert_false(config.timer_allowed)
	assert_eq(config.reward_per_correct, {"apples": 2})
	assert_eq(activity, before)

func _test_question_cannot_be_skipped_or_rewarded_twice() -> void:
	var controller := RunControllerScript.new(FakeClockScript.new())
	assert_true(controller.start(_config({"target_score": 10}), "session-once").ok)
	assert_true(controller.begin_question(_question(1, 1)).ok)
	assert_false(controller.begin_question(_question(2, 2)).ok, "an unanswered question cannot be skipped")
	var transition = controller.plan_answer(1, 5, 0)
	var leaked: Dictionary = transition.next_state
	leaked["score"] = 999
	assert_true(controller.commit(transition).ok)
	assert_eq(controller.snapshot().score, 1, "transition snapshots must be isolated from callers")
	assert_null(controller.plan_answer(1, 5, 0), "a committed question cannot award twice")
	assert_true(controller.begin_question(_question(2, 2)).ok)

func _test_invalid_config_and_question_are_contained() -> void:
	var controller := RunControllerScript.new(FakeClockScript.new())
	var invalid := _config({"initial_health": 0})
	var start_result := controller.start(invalid, "session-invalid")
	assert_false(start_result.ok)
	assert_eq(start_result.error, "invalid_config")
	var malformed_values: Dictionary = _config().to_dict()
	malformed_values["combo_thresholds"] = [2, "four"]
	assert_false(RunControllerScript.new(FakeClockScript.new()).start(RunConfigScript.new(malformed_values), "session-malformed").ok)
	assert_false(controller.begin_question({}).ok)
	assert_null(controller.plan_answer(1, 1, 0))
	var valid := RunControllerScript.new(FakeClockScript.new())
	assert_true(valid.start(_config(), "session-valid").ok)
	var foreign := _question(1, 1)
	foreign["activity_id"] = "foreign"
	var question_result := valid.begin_question(foreign)
	assert_false(question_result.ok)
	assert_eq(question_result.error, "invalid_question")

func _config(overrides: Dictionary = {}) -> RefCounted:
	var values := {
		"activity_id": "foundation_ten_rods",
		"content_version": "a-vertical-1",
		"stage_id": "count_to_10",
		"boss_question_indices": [],
		"initial_health": 3,
		"target_score": 2,
		"timer_allowed": false,
		"timer_duration_ms": 0,
		"reward_per_correct": {"apples": 2},
		"combo_thresholds": [2, 4],
		"effect_intensity": 1.0,
	}
	for key in overrides:
		values[key] = overrides[key]
	return RunConfigScript.new(values)

func _question(seed: int, correct_answer: Variant) -> Dictionary:
	return {
		"question_id": "q-%d" % seed,
		"activity_id": "foundation_ten_rods",
		"content_version": "a-vertical-1",
		"generator_id": "foundation_ten_rods",
		"band_id": "count_to_10",
		"seed": seed,
		"resolved_parameters": {"left": 1, "right": 2},
		"prompt_key": "activity.foundation_ten_rods.add",
		"correct_answer": correct_answer,
		"answer_layout": "numeric_keypad",
		"manipulative": {"kind": "ten_rods"},
	}
