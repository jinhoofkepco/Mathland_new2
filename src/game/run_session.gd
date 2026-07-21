class_name RunSession
extends RefCounted

signal answer_committed(event: Dictionary, transition: RefCounted)
signal run_completed(event: Dictionary, state: Dictionary)
signal persistence_failed(code: String)

const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const RunConfigScript = preload("res://src/game/run_config.gd")
const RunControllerScript = preload("res://src/game/run_controller.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")

var _controller: Variant
var _journal: Variant
var _progress: Variant
var _timestamp_provider: Callable
var _session_id_factory: Callable
var _session_id := ""
var _current_question: Dictionary = {}
var _active := false
var _busy := false
var _blocked := false

func _init(
	controller: Variant = null,
	journal: Variant = null,
	progress: Variant = null,
	timestamp_provider: Callable = Callable(),
	session_id_factory: Callable = Callable()
) -> void:
	_controller = controller if controller != null else RunControllerScript.new()
	_journal = journal
	_progress = progress
	_timestamp_provider = timestamp_provider
	_session_id_factory = session_id_factory

func start_run(activity: Dictionary, first_question: Dictionary) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "busy"}
	if _active:
		return {"ok": false, "error": "already_active"}
	if not _dependencies_are_valid():
		return {"ok": false, "error": "invalid_dependencies"}
	var config := RunConfigScript.from_activity(activity)
	if not config.is_valid():
		return {"ok": false, "error": "invalid_activity"}
	var next_session_id: Variant = _session_id_factory.call() if _session_id_factory.is_valid() else UuidV4Script.generate()
	if not next_session_id is String or next_session_id.is_empty():
		return {"ok": false, "error": "invalid_session"}
	var probe := RunControllerScript.new()
	var probe_started: Variant = probe.start(config, next_session_id)
	if not _successful_result(probe_started):
		return _contained_error(probe_started, "run_start_failed")
	var probe_begun: Variant = probe.begin_question(first_question)
	if not _successful_result(probe_begun):
		return _contained_error(probe_begun, "invalid_question")
	_busy = true
	_blocked = false
	_active = false
	_session_id = next_session_id
	_current_question = {}
	var appended := _append_payload({
		"session_id": _session_id,
		"client_timestamp": _next_timestamp(),
		"event_type": "run_started",
		"activity_id": config.activity_id,
		"content_version": config.content_version,
	})
	if not appended.ok:
		_current_question = {}
		if appended.get("retry_safe", false):
			_busy = false
			_report_persistence_failure(appended.error)
			return appended
		return _fail_stop(appended.error)
	var progress_error := _commit_progress(appended.event)
	if not progress_error.is_empty():
		return _fail_stop(progress_error, appended.event)
	var started: Variant = _controller.start(config, _session_id)
	if not _successful_result(started):
		return _fail_stop("controller_start_%s" % _result_error(started, "failed"), appended.event)
	var begun: Variant = _controller.begin_question(first_question)
	if not _successful_result(begun):
		return _fail_stop("controller_question_%s" % _result_error(begun, "failed"), appended.event)
	_current_question = first_question.duplicate(true)
	_active = true
	_busy = false
	return {
		"ok": true,
		"event": appended.event.duplicate(true),
		"session_id": _session_id,
		"state": _controller.snapshot(),
	}

func begin_question(question: Dictionary) -> Dictionary:
	if _blocked:
		return {"ok": false, "error": "persistence_blocked"}
	if not _active or _busy:
		return {"ok": false, "error": "invalid_state"}
	var result: Variant = _controller.begin_question(question)
	if not _successful_result(result):
		return _contained_error(result, "invalid_question")
	_current_question = question.duplicate(true)
	return {"ok": true, "state": _controller.snapshot()}

func submit_answer(answer: Variant, response_ms: int, hints: int = 0) -> Dictionary:
	var ready := _ready_for_input()
	if not ready.ok:
		return ready
	_busy = true
	var transition: Variant = _controller.plan_answer(answer, response_ms, hints)
	if transition == null:
		_busy = false
		return {"ok": false, "error": "invalid_answer"}
	return _persist_transition(transition)

func expire_question() -> Dictionary:
	var ready := _ready_for_input()
	if not ready.ok:
		return ready
	_busy = true
	var transition: Variant = _controller.plan_timeout()
	if transition == null:
		_busy = false
		return {"ok": false, "error": "invalid_timeout"}
	return _persist_transition(transition)

func snapshot() -> Dictionary:
	if _controller == null or not _controller.has_method("snapshot"):
		return {}
	return _controller.snapshot()

func session_id() -> String:
	return _session_id

func _persist_transition(transition: Variant) -> Dictionary:
	var prepared: Variant = _controller.prepare_commit(transition)
	if not _successful_result(prepared) or not prepared.has("event") or not prepared.event is Object or not prepared.event.has_method("to_dict"):
		_controller.discard(transition)
		_busy = false
		return _contained_error(prepared, "transition_preflight_failed")
	var projection: Object = prepared.event
	var projection_fields: Variant = projection.call("to_dict")
	if not projection_fields is Dictionary:
		_controller.discard(transition)
		_busy = false
		return {"ok": false, "error": "transition_preflight_failed"}
	var appended := _append_payload({
		"session_id": _session_id,
		"client_timestamp": _next_timestamp(),
		"event_type": "answer_submitted",
		"activity_id": _current_question.activity_id,
		"content_version": _current_question.content_version,
		"question_seed": _current_question.seed,
		"generator_id": _current_question.generator_id,
		"band_id": _current_question.band_id,
		"resolved_parameters": _current_question.resolved_parameters.duplicate(true),
		"submitted_answer": _deep_copy(projection_fields.get("submitted_answer")),
		"correct_answer": _deep_copy(projection_fields.get("correct_answer")),
		"correctness": projection_fields.get("correctness"),
		"response_duration_ms": projection_fields.get("response_duration_ms"),
		"hints": projection_fields.get("hints"),
		"health_delta": projection_fields.get("health_delta"),
		"combo": projection_fields.get("combo"),
		"reward_delta": _deep_copy(projection_fields.get("reward_delta")),
	})
	if not appended.ok:
		_controller.discard(transition)
		if appended.get("retry_safe", false):
			_busy = false
			_report_persistence_failure(appended.error)
			return appended
		return _fail_stop(appended.error)
	var transition_data: Variant = transition.to_dict() if transition.has_method("to_dict") else null
	if not transition_data is Dictionary or not transition_data.get("next_state") is Dictionary:
		_controller.discard(transition)
		return _fail_stop("transition_preflight_failed", appended.event)
	var planned_state: Dictionary = transition_data.next_state
	var completion_event: Dictionary = {}
	if planned_state.get("status") == "completed":
		var completion := _append_payload({
			"session_id": _session_id,
			"client_timestamp": _next_timestamp(),
			"event_type": "run_completed",
			"completion_reason": planned_state.completion_reason,
			"final_score": planned_state.score,
			"final_health": planned_state.health,
			"earned_rewards": planned_state.earned_rewards.duplicate(true),
		})
		if not completion.ok:
			_controller.discard(transition)
			return _fail_stop(completion.error, appended.event)
		completion_event = completion.event.duplicate(true)
	var committed: Variant = _controller.commit(transition)
	if not _successful_result(committed):
		_controller.discard(transition)
		return _fail_stop("controller_commit_%s" % _result_error(committed, "failed"), appended.event)
	var committed_state: Dictionary = _controller.snapshot()
	var progress_error := _commit_progress(appended.event)
	if not progress_error.is_empty():
		return _fail_stop(progress_error, appended.event)
	if not completion_event.is_empty():
		progress_error = _commit_progress(completion_event)
		if not progress_error.is_empty():
			return _fail_stop(progress_error, completion_event)
		_active = false
	_busy = false
	var answer_event: Dictionary = appended.event.duplicate(true)
	answer_committed.emit(answer_event.duplicate(true), transition)
	if not completion_event.is_empty():
		run_completed.emit(completion_event.duplicate(true), committed_state.duplicate(true))
	return {
		"ok": true,
		"event": answer_event,
		"completion_event": completion_event.duplicate(true),
		"state": committed_state.duplicate(true),
		"transition": transition,
	}

func _append_payload(payload: Dictionary) -> Dictionary:
	var result: Variant = _journal.append(payload)
	if not result is Dictionary or not result.has("ok") or not result.ok is bool:
		return {"ok": false, "error": "invalid_journal_result", "retry_safe": false}
	if not result.ok:
		var error := _result_error(result, "journal_append_failed")
		return {"ok": false, "error": error, "retry_safe": error != "append_recovery_required"}
	if not result.has("event") or not result.event is Dictionary:
		return {"ok": false, "error": "invalid_journal_result", "retry_safe": false}
	var event: Dictionary = result.event
	if not LearningEventV1Script.validate(event).is_empty():
		return {"ok": false, "error": "invalid_journal_result", "retry_safe": false}
	if event.event_type != payload.get("event_type") or event.get("session_id", "") != _session_id:
		return {"ok": false, "error": "invalid_journal_result", "retry_safe": false}
	for key in payload:
		if not event.has(key) or not _values_equal(event[key], payload[key]):
			return {"ok": false, "error": "invalid_journal_result", "retry_safe": false}
	return {"ok": true, "event": event.duplicate(true)}

func _commit_progress(event: Dictionary) -> String:
	var result: Variant = _progress.commit(event.duplicate(true))
	if not result is int:
		return "invalid_progress_result"
	if int(result) != OK:
		return "progress_commit_%d" % int(result)
	return ""

func _ready_for_input() -> Dictionary:
	if _blocked:
		return {"ok": false, "error": "persistence_blocked"}
	if not _active:
		return {"ok": false, "error": "invalid_state"}
	if _busy:
		return {"ok": false, "error": "busy"}
	return {"ok": true}

func _fail_stop(code: String, event: Dictionary = {}) -> Dictionary:
	_blocked = true
	_active = false
	_busy = false
	_report_persistence_failure(code)
	var result := {"ok": false, "error": code}
	if not event.is_empty():
		result["event"] = event.duplicate(true)
	return result

func _report_persistence_failure(code: String) -> void:
	persistence_failed.emit(code)

func _dependencies_are_valid() -> bool:
	if not _controller is Object or not _journal is Object or not _progress is Object:
		return false
	for method in ["start", "begin_question", "plan_answer", "plan_timeout", "prepare_commit", "discard", "commit", "snapshot"]:
		if not _controller.has_method(method):
			return false
	return _journal.has_method("append") and _progress.has_method("commit")

func _next_timestamp() -> String:
	if _timestamp_provider.is_valid():
		var provided: Variant = _timestamp_provider.call()
		return provided if provided is String else ""
	return "%sZ" % Time.get_datetime_string_from_system(true, false)

func _successful_result(value: Variant) -> bool:
	return value is Dictionary and value.has("ok") and value.ok is bool and value.ok

func _contained_error(value: Variant, fallback: String) -> Dictionary:
	return {"ok": false, "error": _result_error(value, fallback)}

func _result_error(value: Variant, fallback: String) -> String:
	if value is Dictionary and value.get("error", null) is String and not value.error.is_empty():
		return value.error
	return fallback

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

func _values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _values_equal(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _values_equal(left[index], right[index]):
				return false
		return true
	return left == right
