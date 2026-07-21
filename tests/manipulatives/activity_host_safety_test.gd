extends "res://tests/support/test_case.gd"

const ActivityRunScene = preload("res://scenes/game/activity_run.tscn")

class FakeRepository extends RefCounted:
	var activity: Dictionary

	func _init(value: Dictionary) -> void:
		activity = value.duplicate(true)

	func get_activity(_activity_id: StringName, _version := "") -> Dictionary:
		return activity.duplicate(true)


class FixedQuestionEngine extends RefCounted:
	var question: Dictionary
	var requested_seeds: Array[int] = []

	func _init(value: Dictionary) -> void:
		question = value.duplicate(true)

	func generate_question(_activity: Dictionary, _band_id: StringName, seed: int) -> Dictionary:
		requested_seeds.append(seed)
		var result := question.duplicate(true)
		result["seed"] = seed
		return result


class FakeTransition extends RefCounted:
	var _data: Dictionary

	func _init(correctness: bool) -> void:
		_data = {
			"effect_names": ["correct" if correctness else "wrong"],
			"reward_delta": {},
		}

	func to_dict() -> Dictionary:
		return _data.duplicate(true)


class DrivingSession extends RefCounted:
	signal answer_committed(event: Dictionary, transition: RefCounted)
	signal run_completed(event: Dictionary, state: Dictionary)
	signal persistence_failed(code: String)

	var state: Dictionary
	var submissions: Array[Variant] = []
	var begun_seeds: Array[int] = []
	var expiration_count := 0
	var should_expire := false

	func _init(timer_enabled := false, health := 3) -> void:
		state = {
			"status": "running",
			"awaiting_answer": true,
			"health": health,
			"score": 0,
			"timer_enabled": timer_enabled,
		}

	func start_run(_activity: Dictionary, _question: Dictionary) -> Dictionary:
		return {"ok": true, "state": state.duplicate(true)}

	func submit_answer(answer: Variant, _response_ms: int, _hints := 0) -> Dictionary:
		submissions.append(answer.duplicate(true) if answer is Dictionary or answer is Array else answer)
		state.awaiting_answer = false
		var event := {"correctness": true, "reward_delta": {}}
		answer_committed.emit(event.duplicate(true), FakeTransition.new(true))
		return {"ok": true, "state": state.duplicate(true)}

	func expire_question() -> Dictionary:
		if not should_expire or not state.awaiting_answer:
			return {"ok": false, "error": "invalid_timeout"}
		should_expire = false
		expiration_count += 1
		state.awaiting_answer = false
		state.health = maxi(int(state.health) - 1, 0)
		if state.health == 0:
			state.status = "completed"
		var event := {"correctness": false, "reward_delta": {}}
		answer_committed.emit(event.duplicate(true), FakeTransition.new(false))
		if state.status == "completed":
			run_completed.emit({"event_type": "run_completed"}, state.duplicate(true))
		return {"ok": true, "event": event, "state": state.duplicate(true)}

	func begin_question(question: Dictionary) -> Dictionary:
		if state.status != "running" or state.awaiting_answer:
			return {"ok": false, "error": "invalid_state"}
		begun_seeds.append(int(question.get("seed", -1)))
		state.awaiting_answer = true
		return {"ok": true, "state": state.duplicate(true)}

	func time_remaining_ms() -> int:
		return 0 if should_expire else 1000

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func session_id() -> String:
		return "host-safety-session"

	func is_blocked() -> bool:
		return false


class RecordingRouter extends RefCounted:
	var replacements: Array[StringName] = []

	func replace(route: StringName, _params: Dictionary) -> Dictionary:
		replacements.append(route)
		return {"ok": true}


class RecordingAudio extends RefCounted:
	var played: Array[StringName] = []

	func play_sfx(id: StringName) -> bool:
		played.append(id)
		return true

	func stop_voice() -> void:
		pass


func run(tree: SceneTree) -> void:
	await _test_enabled_timer_expires_and_advances_until_health_depletion(tree)
	await _test_manipulative_submission_is_gated_by_layout(tree)
	await _test_uint32_seed_rolls_over_deterministically(tree)
	await _test_internal_tactile_sfx_reaches_host_audio(tree)


func _test_enabled_timer_expires_and_advances_until_health_depletion(tree: SceneTree) -> void:
	var session := DrivingSession.new(true, 3)
	var screen := _screen(
		_activity("addition", "numeric_keypad", "none", true),
		_question("addition", "numeric_keypad", "none"),
		session,
		FixedQuestionEngine.new(_question("addition", "numeric_keypad", "none")),
		{"router": RecordingRouter.new()}
	)
	tree.root.add_child(screen)
	await tree.process_frame
	screen.skip_introduction()
	assert_true(screen.has_method("_process"), "ActivityRun must poll enabled question timers")
	if not screen.has_method("_process"):
		screen.queue_free()
		await tree.process_frame
		return

	for expected_health in [2, 1]:
		session.should_expire = true
		screen.call("_process", 0.016)
		assert_eq(session.expiration_count, 3 - expected_health)
		assert_eq(screen.current_state().health, expected_health)
		assert_true(screen.can_answer(), "a committed timeout permanently disabled the next question")

	session.should_expire = true
	screen.call("_process", 0.016)
	assert_eq(session.expiration_count, 3)
	assert_eq(session.begun_seeds.size(), 2, "non-terminal timeouts must begin exactly one next question")
	assert_eq(screen.current_state().health, 0)
	assert_eq(screen.current_state().status, "completed")
	assert_false(screen.can_answer())
	screen.queue_free()
	await tree.process_frame


func _test_manipulative_submission_is_gated_by_layout(tree: SceneTree) -> void:
	var supplemental_session := DrivingSession.new()
	var supplemental := _screen(
		_activity("counting", "numeric_keypad", "counters"),
		_question("counting", "numeric_keypad", "counters"),
		supplemental_session,
		FixedQuestionEngine.new(_question("counting", "numeric_keypad", "counters"))
	)
	tree.root.add_child(supplemental)
	await tree.process_frame
	supplemental.skip_introduction()
	var supplemental_manipulative: Control = supplemental.find_child("Manipulative", true, false)
	assert_not_null(supplemental_manipulative)
	if supplemental_manipulative != null:
		supplemental_manipulative.submit_current_answer()
	assert_eq(supplemental_session.submissions, [], "a visual aid bypassed the configured answer input")
	supplemental.queue_free()
	await tree.process_frame

	var submit_session := DrivingSession.new()
	var submit_host := _screen(
		_activity("counting", "manipulative_submit", "counters"),
		_question("counting", "manipulative_submit", "counters"),
		submit_session,
		FixedQuestionEngine.new(_question("counting", "manipulative_submit", "counters"))
	)
	tree.root.add_child(submit_host)
	await tree.process_frame
	submit_host.skip_introduction()
	var submitting_manipulative: Control = submit_host.find_child("Manipulative", true, false)
	assert_not_null(submitting_manipulative)
	if submitting_manipulative != null:
		submitting_manipulative.submit_current_answer()
	assert_eq(submit_session.submissions, [{"kind": "integer", "value": 0}])
	submit_host.queue_free()
	await tree.process_frame


func _test_uint32_seed_rolls_over_deterministically(tree: SceneTree) -> void:
	var session := DrivingSession.new()
	var engine := FixedQuestionEngine.new(_question("addition", "numeric_keypad", "none"))
	var screen := _screen(
		_activity("addition", "numeric_keypad", "none"),
		_question("addition", "numeric_keypad", "none"),
		session,
		engine,
		{"seed": 0xFFFFFFFF}
	)
	tree.root.add_child(screen)
	await tree.process_frame
	screen.skip_introduction()
	for expected_seed in [0, 1]:
		var input: Control = screen.find_child("AnswerInput", true, false)
		assert_not_null(input)
		if input != null:
			input.set_integer(1)
			input.submit_current_answer()
		assert_eq(screen.current_question().seed, expected_seed)
	assert_eq(engine.requested_seeds, [0xFFFFFFFF, 0, 1])
	assert_eq(session.begun_seeds, [0, 1])
	screen.queue_free()
	await tree.process_frame


func _test_internal_tactile_sfx_reaches_host_audio(tree: SceneTree) -> void:
	for manipulative_id in ["counters", "ten_frame", "base_ten", "number_line", "answer_slots"]:
		var audio := RecordingAudio.new()
		var question := _question("foundation", "manipulative_submit", manipulative_id)
		var screen := _screen(
			_activity("foundation", "manipulative_submit", manipulative_id),
			question,
			DrivingSession.new(),
			FixedQuestionEngine.new(question),
			{"audio_service": audio}
		)
		tree.root.add_child(screen)
		await tree.process_frame
		var root: Control = screen.find_child("Manipulative", true, false)
		var button := _first_sfx_control(root)
		assert_not_null(button, manipulative_id)
		if button != null:
			button.emit_signal("sfx_requested", &"button_down")
		assert_eq(audio.played, [&"button_down"], manipulative_id)
		screen.queue_free()
		await tree.process_frame

	for layout_id in ["numeric_keypad", "choice_grid", "factor_slots"]:
		var audio := RecordingAudio.new()
		var question := _question("arithmetic", layout_id, "none")
		var screen := _screen(
			_activity("arithmetic", layout_id, "none"),
			question,
			DrivingSession.new(),
			FixedQuestionEngine.new(question),
			{"audio_service": audio}
		)
		tree.root.add_child(screen)
		await tree.process_frame
		var root: Control = screen.find_child("AnswerInput", true, false)
		var button := _first_sfx_control(root)
		assert_not_null(button, layout_id)
		if button != null:
			button.emit_signal("sfx_requested", &"button_down")
		assert_eq(audio.played, [&"button_down"], layout_id)
		screen.queue_free()
		await tree.process_frame


func _screen(
	activity: Dictionary,
	question: Dictionary,
	session: RefCounted,
	engine: RefCounted,
	extra: Dictionary = {}
) -> Control:
	var screen: Control = ActivityRunScene.instantiate()
	var repository := FakeRepository.new(activity)
	var params := {
		"activity_id": activity.activity_id,
		"content_repository": repository,
		"question_engine": engine,
		"run_session": session,
	}
	for key in extra:
		params[key] = extra[key]
	screen.configure(params)
	return screen


func _activity(
	activity_id: String,
	layout_id: String,
	manipulative_id: String,
	timer_enabled := false
) -> Dictionary:
	return {
		"schema_version": 1,
		"activity_id": activity_id,
		"content_version": "1.0.0",
		"localizations": {"ko-KR": {"title": "Test", "description": "Test", "tutorial_steps": ["Test"]}},
		"run": {
			"starting_hearts": 3,
			"goal": {"kind": "correct_answers", "target": 99},
			"timer": {"enabled": timer_enabled, "seconds": 1, "profile_can_disable": true},
			"rewards": {"apples_per_correct": 0, "completion_apples": 0},
			"combo_thresholds": [2, 4, 7],
			"boss_every_correct": 0,
			"effects": {
				"correct": "correct", "wrong": "wrong", "combo": "combo",
				"boss": "boss", "level_up": "level_up", "reward": "reward",
				"health_loss": "health_loss",
			},
		},
		"difficulty_bands": [{
			"band_id": "intro",
			"generator_id": "addition_v1",
			"generator_parameters": {},
			"answer_layout": {"id": layout_id},
			"manipulative": {"id": manipulative_id, "config": _manipulative_config(manipulative_id), "initial_state": {}},
		}],
		"adaptive_policy": {"enabled_by_default": false},
	}


func _question(activity_id: String, layout_id: String, manipulative_id: String) -> Dictionary:
	var answer := (
		{"kind": "integer_list", "values": [2], "order_matters": false}
		if layout_id == "factor_slots" or manipulative_id == "answer_slots"
		else {"kind": "integer", "value": 1}
	)
	var layout := {"id": layout_id}
	if layout_id == "choice_grid":
		layout["options"] = {"values": [1, 2, 3]}
	elif layout_id == "factor_slots":
		layout["options"] = {"allowed_values": [2, 3, 5], "slot_count": 4}
	return {
		"contract_version": 1,
		"activity_id": activity_id,
		"content_version": "1.0.0",
		"generator_id": "addition_v1",
		"band_id": "intro",
		"seed": 42,
		"resolved_parameters": {"axis_min": 0, "axis_max": 10, "start": 0, "allowed_primes": [2, 3, 5]},
		"prompt": {"key": "question.test", "args": {}},
		"correct_answer": answer,
		"answer_layout": layout,
		"manipulative": {"id": manipulative_id, "config": _manipulative_config(manipulative_id), "initial_state": {}},
	}


func _manipulative_config(id: String) -> Dictionary:
	match id:
		"counters":
			return {"capacity": 10}
		"ten_frame":
			return {"frame_count": 1}
		"base_ten":
			return {"max_place": "hundreds"}
		"number_line":
			return {"axis_min": 0, "axis_max": 10}
		"answer_slots":
			return {"slot_count": 4, "allowed_values": [2, 3, 5]}
	return {}


func _first_sfx_control(root: Node) -> Control:
	if root == null:
		return null
	if root is Control and root.has_signal("sfx_requested"):
		return root
	for candidate in root.find_children("*", "Control", true, false):
		if candidate.has_signal("sfx_requested"):
			return candidate
	return null
