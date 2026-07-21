extends "res://tests/support/test_case.gd"

const FakeClockScript = preload("res://tests/support/fake_clock.gd")
const InMemoryProgressServiceScript = preload("res://tests/support/in_memory_progress_service.gd")
const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const RecordingJournalScript = preload("res://tests/support/recording_journal.gd")
const RunControllerScript = preload("res://src/game/run_controller.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const VerticalSliceQuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")

func run(_tree: SceneTree) -> void:
	_test_run_start_failure_does_not_publish_controller_state()
	_test_answer_is_journaled_then_reduced_then_signalled()
	_test_journal_failure_leaves_state_unchanged_and_retryable()
	_test_uncertain_journal_result_is_fail_stopped()
	_test_fail_stop_blocks_reentrant_and_later_run_start()
	_test_malformed_journal_failures_are_fail_stopped()
	_test_journal_cannot_substitute_a_different_valid_event()
	_test_terminal_answer_persists_completion_before_signals()
	_test_terminal_completion_failure_emits_no_presentation()
	_test_timeout_uses_the_same_persistence_boundary()
	_test_committed_signal_can_begin_the_next_question()
	_test_progress_failure_is_fail_stopped_after_durable_append()

func _test_run_start_failure_does_not_publish_controller_state() -> void:
	var fixture := _fixture()
	var before: Dictionary = fixture.controller.snapshot()
	fixture.journal.fail_next_error = "disk_full"
	var result: Dictionary = fixture.session.start_run(fixture.activity, fixture.question)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "disk_full")
	assert_eq(fixture.controller.snapshot(), before, "failed run_started persistence changed controller state")
	assert_eq(fixture.progress.snapshot().last_sequence, 0)
	assert_eq(fixture.journal.events, [])
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok, "safe start failure was not retryable")

func _test_answer_is_journaled_then_reduced_then_signalled() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	var operations: Array[String] = fixture.operations
	var emitted: Array[Dictionary] = []
	fixture.session.answer_committed.connect(func(event: Dictionary, _transition):
		operations.append("signal")
		emitted.append(event.duplicate(true))
	)
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 1250, 1)
	assert_true(result.ok)
	assert_eq(fixture.operations, ["journal.append", "progress.commit", "signal"])
	assert_eq(emitted.size(), 1)
	assert_eq(LearningEventV1Script.validate(emitted[0]), PackedStringArray())
	assert_eq(emitted[0].event_type, "answer_submitted")
	assert_eq(emitted[0].sequence, 2)
	assert_eq(emitted[0].session_id, "session-test")
	assert_eq(emitted[0].question_seed, fixture.question.seed)
	assert_eq(emitted[0].resolved_parameters, fixture.question.resolved_parameters)
	assert_eq(emitted[0].submitted_answer, fixture.question.correct_answer)
	assert_true(emitted[0].correctness)
	assert_eq(emitted[0].response_duration_ms, 1250)
	assert_eq(emitted[0].hints, 1)
	assert_eq(fixture.controller.snapshot().score, 1)
	assert_eq(fixture.progress.snapshot().last_sequence, 2)

func _test_journal_failure_leaves_state_unchanged_and_retryable() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	var committed_count := [0]
	var failures: Array[String] = []
	fixture.session.answer_committed.connect(func(_event, _transition): committed_count[0] += 1)
	fixture.session.persistence_failed.connect(func(code: String): failures.append(code))
	var before: Dictionary = fixture.controller.snapshot()
	fixture.journal.fail_next_error = "disk_full"
	var failed: Dictionary = fixture.session.submit_answer(999, 250, 0)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "disk_full")
	assert_eq(fixture.controller.snapshot(), before)
	assert_eq(fixture.operations, ["journal.append"])
	assert_eq(committed_count[0], 0)
	assert_eq(failures, ["disk_full"])
	fixture.operations.clear()
	var retry: Dictionary = fixture.session.submit_answer(999, 250, 0)
	assert_true(retry.ok)
	assert_eq(fixture.operations, ["journal.append", "progress.commit"])
	assert_eq(fixture.controller.snapshot().health, before.health - 1)
	assert_eq(fixture.journal.events.map(func(event): return event.sequence), [1, 2])

func _test_uncertain_journal_result_is_fail_stopped() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var before: Dictionary = fixture.controller.snapshot()
	var failures: Array[String] = []
	fixture.session.persistence_failed.connect(func(code: String): failures.append(code))
	fixture.journal.malformed_success_next = true
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "invalid_journal_result")
	assert_eq(fixture.journal.events.size(), 2, "uncertain append did not preserve its durable artifact")
	assert_eq(fixture.controller.snapshot(), before)
	assert_eq(failures, ["invalid_journal_result"])
	assert_eq(fixture.session.submit_answer(fixture.question.correct_answer, 100, 0).get("error", ""), "persistence_blocked")

func _test_fail_stop_blocks_reentrant_and_later_run_start() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	var before: Dictionary = fixture.controller.snapshot()
	var attempted := [false]
	var reentrant_starts: Array[Dictionary] = []
	var session = fixture.session
	var handler := func(_code: String):
		if attempted[0]:
			return
		attempted[0] = true
		reentrant_starts.append(session.start_run(fixture.activity, fixture.question))
	fixture.session.persistence_failed.connect(handler)
	fixture.journal.fail_next_error = "append_recovery_required"
	var failed: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	fixture.session.persistence_failed.disconnect(handler)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "append_recovery_required")
	assert_eq(reentrant_starts.size(), 1)
	assert_eq(reentrant_starts[0].get("error", ""), "persistence_blocked")
	assert_eq(fixture.operations, ["journal.append"], "reentrant start touched persistence after fail-stop")
	assert_eq(fixture.controller.snapshot(), before)
	assert_eq(fixture.journal.events.size(), 1)
	assert_eq(fixture.progress.snapshot().last_sequence, 1)
	fixture.operations.clear()
	var later_start: Dictionary = fixture.session.start_run(fixture.activity, fixture.question)
	assert_false(later_start.ok)
	assert_eq(later_start.get("error", ""), "persistence_blocked")
	assert_eq(fixture.operations, [], "blocked start touched persistence dependencies")

func _test_malformed_journal_failures_are_fail_stopped() -> void:
	var cases := [
		{"name": "missing error", "result": {"ok": false}},
		{"name": "non-string error", "result": {"ok": false, "error": 17}},
		{"name": "empty error", "result": {"ok": false, "error": ""}},
	]
	for case in cases:
		var fixture := _fixture()
		assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
		fixture.operations.clear()
		var before: Dictionary = fixture.controller.snapshot()
		var failures: Array[String] = []
		fixture.session.persistence_failed.connect(func(code: String): failures.append(code))
		fixture.journal.malformed_failure_next = case.result.duplicate(true)
		var failed: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
		assert_false(failed.ok)
		assert_eq(failed.get("error", ""), "invalid_journal_result", case.name)
		assert_eq(failures, ["invalid_journal_result"], case.name)
		assert_eq(fixture.journal.events.size(), 2, "%s lost the uncertain durable event" % case.name)
		assert_eq(fixture.progress.snapshot().last_sequence, 1, case.name)
		assert_eq(fixture.controller.snapshot(), before, case.name)
		fixture.operations.clear()
		var later_start: Dictionary = fixture.session.start_run(fixture.activity, fixture.question)
		var retry: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
		assert_eq(later_start.get("error", ""), "persistence_blocked", case.name)
		assert_eq(retry.get("error", ""), "persistence_blocked", case.name)
		assert_eq(fixture.operations, [], "%s allowed persistence after an indeterminate append" % case.name)
		assert_eq(fixture.journal.events.size(), 2, case.name)
		assert_eq(fixture.progress.snapshot().last_sequence, 1, case.name)
		assert_eq(fixture.controller.snapshot(), before, case.name)

func _test_journal_cannot_substitute_a_different_valid_event() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var before: Dictionary = fixture.controller.snapshot()
	fixture.journal.next_event_overrides = {"correctness": false, "health_delta": -1}
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "invalid_journal_result")
	assert_eq(fixture.journal.events.size(), 2)
	assert_false(fixture.journal.events[-1].correctness)
	assert_eq(fixture.controller.snapshot(), before, "substituted journal data was committed as canonical state")
	assert_eq(fixture.session.submit_answer(fixture.question.correct_answer, 100, 0).get("error", ""), "persistence_blocked")

func _test_terminal_answer_persists_completion_before_signals() -> void:
	var fixture := _fixture({"target_score": 1})
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	var operations: Array[String] = fixture.operations
	var answer_events: Array[Dictionary] = []
	var completion_events: Array[Dictionary] = []
	fixture.session.answer_committed.connect(func(event: Dictionary, _transition):
		operations.append("answer.signal")
		answer_events.append(event.duplicate(true))
	)
	fixture.session.run_completed.connect(func(event: Dictionary, _state: Dictionary):
		operations.append("run.signal")
		completion_events.append(event.duplicate(true))
	)
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 500, 0)
	assert_true(result.ok)
	assert_eq(fixture.operations, [
		"journal.append",
		"journal.append",
		"progress.commit",
		"progress.commit",
		"answer.signal",
		"run.signal",
	])
	assert_eq(answer_events.size(), 1)
	assert_eq(completion_events.size(), 1)
	assert_eq(completion_events[0].event_type, "run_completed")
	assert_eq(completion_events[0].sequence, 3)
	assert_eq(completion_events[0].completion_reason, "target_reached")
	assert_eq(completion_events[0].final_score, 1)
	assert_eq(completion_events[0].final_health, 3)
	assert_eq(completion_events[0].earned_rewards, {"apples": 2})
	assert_eq(fixture.progress.snapshot().last_sequence, 3)
	assert_eq(fixture.controller.snapshot().status, "completed")

func _test_terminal_completion_failure_emits_no_presentation() -> void:
	var fixture := _fixture({"target_score": 1})
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	fixture.journal.fail_event_type = "run_completed"
	var before: Dictionary = fixture.controller.snapshot()
	var answer_count := [0]
	var completion_count := [0]
	var failures: Array[String] = []
	fixture.session.answer_committed.connect(func(_event, _transition): answer_count[0] += 1)
	fixture.session.run_completed.connect(func(_event, _state): completion_count[0] += 1)
	fixture.session.persistence_failed.connect(func(code: String): failures.append(code))
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "disk_full")
	assert_eq(fixture.operations, ["journal.append", "journal.append"])
	assert_eq(fixture.journal.events.map(func(event): return event.event_type), ["run_started", "answer_submitted"])
	assert_eq(fixture.progress.snapshot().last_sequence, 1)
	assert_eq(fixture.controller.snapshot(), before, "failed completion persistence committed the planned transition")
	assert_eq(answer_count[0], 0)
	assert_eq(completion_count[0], 0)
	assert_eq(failures, ["disk_full"])
	assert_eq(fixture.session.begin_question(_question(fixture.activity, 100)).get("error", ""), "persistence_blocked")

func _test_timeout_uses_the_same_persistence_boundary() -> void:
	var fixture := _fixture({"timer": {"enabled": true, "duration_ms": 1}})
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	fixture.clock.advance_ms(1)
	var result: Dictionary = fixture.session.expire_question()
	assert_true(result.ok)
	assert_eq(fixture.operations, ["journal.append", "progress.commit"])
	assert_eq(result.event.event_type, "answer_submitted")
	assert_false(result.event.correctness)
	assert_eq(result.event.health_delta, -1)
	assert_eq(fixture.controller.snapshot().health, 2)

func _test_committed_signal_can_begin_the_next_question() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var next_question := _question(fixture.activity, 77)
	var session = fixture.session
	var begin_results: Array[Dictionary] = []
	var handler := func(_event, _transition): begin_results.append(session.begin_question(next_question))
	session.answer_committed.connect(handler)
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	session.answer_committed.disconnect(handler)
	assert_true(result.ok)
	assert_eq(begin_results.size(), 1)
	assert_true(begin_results[0].get("ok", false), "answer_committed could not advance to the next question")
	assert_true(fixture.controller.snapshot().awaiting_answer)
	assert_eq(fixture.controller.snapshot().current_seed, 77)

func _test_progress_failure_is_fail_stopped_after_durable_append() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	fixture.operations.clear()
	var committed_count := [0]
	var failures: Array[String] = []
	fixture.session.answer_committed.connect(func(_event, _transition): committed_count[0] += 1)
	fixture.session.persistence_failed.connect(func(code: String): failures.append(code))
	fixture.progress.fail_next_error = ERR_CANT_CREATE
	var result: Dictionary = fixture.session.submit_answer(fixture.question.correct_answer, 100, 0)
	assert_false(result.ok)
	assert_true(result.get("error", "").begins_with("progress_commit_"))
	assert_eq(fixture.operations, ["journal.append", "progress.commit"])
	assert_eq(fixture.journal.events.size(), 2, "the durable append was lost")
	assert_eq(fixture.controller.snapshot().score, 1, "controller diverged from the durable journal")
	assert_eq(committed_count[0], 0)
	assert_eq(failures.size(), 1)
	assert_false(fixture.session.begin_question(_question(fixture.activity, 99)).ok, "a fail-stopped session accepted more input")

func _fixture(activity_overrides: Dictionary = {}) -> Dictionary:
	var operations: Array[String] = []
	var activity := VerticalSliceContentRepositoryScript.new().get_activity(&"foundation_ten_rods")
	for key in activity_overrides:
		activity[key] = activity_overrides[key]
	var question := _question(activity, 42)
	var clock := FakeClockScript.new(1000)
	var controller := RunControllerScript.new(clock)
	var journal := RecordingJournalScript.new("profile-a", "device-a", operations)
	var progress := InMemoryProgressServiceScript.new("profile-a", operations)
	var session := RunSessionScript.new(
		controller,
		journal,
		progress,
		func(): return "2026-07-21T09:00:00Z",
		func(): return "session-test"
	)
	return {
		"activity": activity,
		"clock": clock,
		"controller": controller,
		"journal": journal,
		"operations": operations,
		"progress": progress,
		"question": question,
		"session": session,
	}

func _question(activity: Dictionary, seed: int) -> Dictionary:
	return VerticalSliceQuestionEngineScript.new().generate_question(activity, &"count_to_10", seed)
