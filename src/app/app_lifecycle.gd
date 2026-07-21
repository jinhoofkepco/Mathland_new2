class_name AppLifecycle
extends Node

signal checkpoint_saved(profile_id: String, session_id: String)
signal run_restored(profile_id: String, session_id: String, source: String)
signal diagnostic(code: String)

const AppRouteScript = preload("res://src/app/app_route.gd")
const RunCheckpointStoreScript = preload("res://src/persistence/run_checkpoint_store.gd")
const RunConfigScript = preload("res://src/game/run_config.gd")
const RunControllerScript = preload("res://src/game/run_controller.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")
const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const VerticalSliceQuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")

var _checkpoint_store: Variant
var _content_repository: Variant
var _question_engine: Variant
var _profile_id := ""
var _journal: Variant
var _progress: Variant
var _router: Variant
var _active_session: Variant
var _active_activity: Dictionary = {}

func _init(
	checkpoint_store: Variant = null,
	content_repository: Variant = null,
	question_engine: Variant = null
) -> void:
	_checkpoint_store = checkpoint_store if checkpoint_store != null else RunCheckpointStoreScript.new()
	_content_repository = content_repository if content_repository != null else VerticalSliceContentRepositoryScript.new()
	_question_engine = question_engine if question_engine != null else VerticalSliceQuestionEngineScript.new()

func configure(profile_id: String, journal: Variant, progress: Variant, router: Variant = null) -> Dictionary:
	if (
		not UuidV4Script.is_valid(profile_id)
		or journal == null
		or not journal.has_method("replay")
		or not journal.has_method("flush")
		or progress == null
		or not progress.has_method("commit")
		or not progress.has_method("snapshot")
		or _checkpoint_store == null
		or not _checkpoint_store.has_method("save")
		or not _checkpoint_store.has_method("load")
		or not _checkpoint_store.has_method("delete")
	):
		return {"ok": false, "error": "invalid_lifecycle_dependencies"}
	_clear_active_run()
	_profile_id = profile_id
	_journal = journal
	_progress = progress
	_router = router
	return {"ok": true}

func bind_active_run(run_session: Variant, activity: Dictionary) -> Dictionary:
	if _profile_id.is_empty() or not _is_session_interface(run_session):
		return {"ok": false, "error": "invalid_run_session"}
	var state: Dictionary = run_session.snapshot()
	if not _activity_matches_state(activity, state) or state.get("status") != "running":
		return {"ok": false, "error": "invalid_run_state"}
	_clear_active_run()
	_active_session = run_session
	_active_activity = activity.duplicate(true)
	var completion_callable := Callable(self, "_on_run_completed")
	if not _active_session.run_completed.is_connected(completion_callable):
		_active_session.run_completed.connect(completion_callable)
	return {"ok": true}

func flush_and_checkpoint() -> Dictionary:
	if _active_session == null or not _is_session_interface(_active_session):
		return {"ok": false, "error": "no_active_run"}
	var state: Dictionary = _active_session.snapshot()
	if state.get("status") != "running":
		var deleted: Dictionary = _checkpoint_store.delete(_profile_id)
		_clear_active_run()
		return deleted if not deleted.get("ok", false) else {"ok": false, "error": "no_active_run"}
	var flush_error: Variant = _journal.flush()
	if not flush_error is int or int(flush_error) != OK:
		diagnostic.emit("journal_flush_failed")
		return {"ok": false, "error": "journal_flush_failed"}
	var replayed := _validated_replay()
	if not replayed.get("ok", false):
		diagnostic.emit(String(replayed.get("error", "journal_replay_failed")))
		return replayed
	var current_question: Variant = state.get("current_question")
	if not current_question is Dictionary or current_question.is_empty():
		return {"ok": false, "error": "invalid_run_state"}
	var checkpoint := {
		"schema_version": 1,
		"profile_id": _profile_id,
		"session_id": _active_session.session_id(),
		"content_version": String(state.get("content_version", "")),
		"activity_id": String(state.get("activity_id", "")),
		"run_state": state.duplicate(true),
		"current_question": current_question.duplicate(true),
		"last_event_sequence": replayed.last_sequence,
	}
	var saved: Dictionary = _checkpoint_store.save(checkpoint)
	if not saved.get("ok", false):
		diagnostic.emit(String(saved.get("error", "checkpoint_save_failed")))
		return saved
	checkpoint_saved.emit(_profile_id, checkpoint.session_id)
	return {"ok": true, "checkpoint": checkpoint.duplicate(true)}

func restore_if_present() -> Dictionary:
	if _profile_id.is_empty() or _journal == null or _progress == null:
		return {"ok": false, "error": "lifecycle_unconfigured"}
	var loaded: Dictionary = _checkpoint_store.load(_profile_id)
	if not loaded.get("ok", false):
		if loaded.get("error") == "not_found":
			return {"ok": true, "restored": false}
		diagnostic.emit(String(loaded.get("error", "checkpoint_load_failed")))
		return loaded
	var checkpoint: Dictionary = loaded.checkpoint
	if _content_repository == null or not _content_repository.has_method("get_activity"):
		return {"ok": false, "error": "content_unavailable"}
	var activity_value: Variant = _content_repository.get_activity(
		StringName(checkpoint.activity_id), checkpoint.content_version
	)
	if not activity_value is Dictionary or activity_value.is_empty():
		return {"ok": false, "error": "content_unavailable"}
	var activity: Dictionary = activity_value.duplicate(true)
	var replayed := _validated_replay()
	if not replayed.get("ok", false):
		return replayed
	if _session_was_superseded(replayed.events, checkpoint.session_id):
		var discard: Dictionary = _checkpoint_store.delete(_profile_id)
		return discard if not discard.get("ok", false) else {"ok": true, "restored": false, "source": "superseded"}
	var source := "checkpoint"
	var state: Dictionary = checkpoint.run_state.duplicate(true)
	var current_question: Dictionary = checkpoint.current_question.duplicate(true)
	var reconstructed := _replay_run(activity, checkpoint, replayed.events)
	if not reconstructed.get("ok", false):
		diagnostic.emit(String(reconstructed.get("error", "run_replay_failed")))
		return reconstructed
	if reconstructed.get("completed", false):
		var removed: Dictionary = _checkpoint_store.delete(_profile_id)
		return removed if not removed.get("ok", false) else {"ok": true, "restored": false, "source": "journal_replay"}
	if (
		int(checkpoint.last_event_sequence) != int(replayed.last_sequence)
		or not _values_equal(state, reconstructed.state)
		or not _values_equal(current_question, reconstructed.current_question)
	):
		state = reconstructed.state.duplicate(true)
		current_question = reconstructed.current_question.duplicate(true)
		source = "journal_replay"
	var session := RunSessionScript.new(null, _journal, _progress)
	if not session.has_method("restore_run"):
		return {"ok": false, "error": "restore_unavailable"}
	var restored_session: Variant = session.restore_run(activity, state, current_question)
	if not restored_session is Dictionary or not restored_session.get("ok", false):
		return restored_session if restored_session is Dictionary else {"ok": false, "error": "restore_failed"}
	var bound := bind_active_run(session, activity)
	if not bound.get("ok", false):
		return bound
	var refreshed := {
		"schema_version": 1,
		"profile_id": _profile_id,
		"session_id": session.session_id(),
		"content_version": checkpoint.content_version,
		"activity_id": checkpoint.activity_id,
		"run_state": state.duplicate(true),
		"current_question": current_question.duplicate(true),
		"last_event_sequence": replayed.last_sequence,
	}
	if source == "journal_replay":
		var saved: Dictionary = _checkpoint_store.save(refreshed)
		if not saved.get("ok", false):
			_clear_active_run()
			return saved
	run_restored.emit(_profile_id, session.session_id(), source)
	return {
		"ok": true,
		"restored": true,
		"source": source,
		"route": AppRouteScript.ACTIVITY_RUN,
		"activity": activity.duplicate(true),
		"run_session": session,
		"state": state.duplicate(true),
		"current_question": current_question.duplicate(true),
	}

func _notification(what: int) -> void:
	if what == Object.NOTIFICATION_PREDELETE:
		_clear_active_run()
		return
	if what in [MainLoop.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_WM_GO_BACK_REQUEST]:
		flush_and_checkpoint()

func _on_run_completed(_event: Dictionary, _state: Dictionary) -> void:
	if _profile_id.is_empty():
		return
	var removed: Dictionary = _checkpoint_store.delete(_profile_id)
	if not removed.get("ok", false):
		diagnostic.emit(String(removed.get("error", "checkpoint_delete_failed")))
	_clear_active_run()

func _replay_run(activity: Dictionary, checkpoint: Dictionary, events: Array) -> Dictionary:
	if _question_engine == null or not _question_engine.has_method("generate_question"):
		return {"ok": false, "error": "question_engine_unavailable"}
	var config := RunConfigScript.from_activity(activity)
	if not config.is_valid():
		return {"ok": false, "error": "invalid_activity"}
	var controller := RunControllerScript.new()
	var started: Variant = controller.start(config, checkpoint.session_id)
	if not started is Dictionary or not started.get("ok", false):
		return {"ok": false, "error": "run_replay_failed"}
	var saw_start := false
	var saw_completion := false
	var last_answer_seed := -1
	for event_value in events:
		if not event_value is Dictionary:
			return {"ok": false, "error": "invalid_replay_result"}
		var event: Dictionary = event_value
		if event.get("session_id", "") != checkpoint.session_id:
			continue
		match String(event.get("event_type", "")):
			"run_started":
				if saw_start or event.get("activity_id") != checkpoint.activity_id or event.get("content_version") != checkpoint.content_version:
					return {"ok": false, "error": "invalid_run_replay"}
				saw_start = true
			"answer_submitted":
				if not saw_start or saw_completion:
					return {"ok": false, "error": "invalid_run_replay"}
				var question_value: Variant = _question_engine.generate_question(activity, StringName(event.band_id), int(event.question_seed))
				if not question_value is Dictionary or not _question_matches_event(question_value, event):
					return {"ok": false, "error": "question_replay_mismatch"}
				var question: Dictionary = question_value
				var begun: Variant = controller.begin_question(question)
				if not begun is Dictionary or not begun.get("ok", false):
					return {"ok": false, "error": "invalid_run_replay"}
				var transition: Variant = controller.plan_answer(event.submitted_answer, int(event.response_duration_ms), int(event.hints))
				if transition == null:
					return {"ok": false, "error": "invalid_run_replay"}
				var prepared: Dictionary = controller.prepare_commit(transition)
				if not prepared.get("ok", false) or not _projection_matches_event(prepared.event.to_dict(), event):
					return {"ok": false, "error": "event_replay_mismatch"}
				var committed: Dictionary = controller.commit(transition)
				if not committed.get("ok", false):
					return {"ok": false, "error": "invalid_run_replay"}
				last_answer_seed = int(event.question_seed)
			"run_completed":
				if not saw_start or saw_completion or not _completion_matches_state(event, controller.snapshot()):
					return {"ok": false, "error": "completion_replay_mismatch"}
				saw_completion = true
	if not saw_start:
		return {"ok": false, "error": "run_start_missing"}
	var state: Dictionary = controller.snapshot()
	if saw_completion:
		return {"ok": true, "completed": true, "state": state}
	var next_question: Dictionary
	if last_answer_seed >= 0:
		var generated: Variant = _question_engine.generate_question(activity, StringName(state.stage_id), last_answer_seed + 1)
		if not generated is Dictionary:
			return {"ok": false, "error": "question_replay_failed"}
		next_question = generated
	else:
		var regenerated: Variant = _question_engine.generate_question(
			activity,
			StringName(checkpoint.current_question.band_id),
			int(checkpoint.current_question.seed)
		)
		if not regenerated is Dictionary or not _values_equal(regenerated, checkpoint.current_question):
			return {"ok": false, "error": "question_replay_mismatch"}
		next_question = regenerated
	var next_begun: Variant = controller.begin_question(next_question)
	if not next_begun is Dictionary or not next_begun.get("ok", false):
		return {"ok": false, "error": "invalid_run_replay"}
	return {"ok": true, "completed": false, "state": controller.snapshot(), "current_question": next_question.duplicate(true)}

func _validated_replay() -> Dictionary:
	var replayed: Variant = _journal.replay()
	if not replayed is Dictionary or not replayed.get("ok", false) or not replayed.get("events", null) is Array:
		return {"ok": false, "error": "journal_replay_failed"}
	var last_sequence := 0
	var expected_sequence := 1
	for event in replayed.events:
		if not event is Dictionary or event.get("profile_id", "") != _profile_id or event.get("sequence") != expected_sequence:
			return {"ok": false, "error": "invalid_replay_result"}
		last_sequence = expected_sequence
		expected_sequence += 1
	return {"ok": true, "events": replayed.events.duplicate(true), "last_sequence": last_sequence}

func _session_was_superseded(events: Array, session_id: String) -> bool:
	var saw_session := false
	for event in events:
		if event.get("event_type") != "run_started":
			continue
		if event.get("session_id") == session_id:
			saw_session = true
		elif saw_session:
			return true
	return false

func _question_matches_event(question: Dictionary, event: Dictionary) -> bool:
	for key in ["activity_id", "content_version", "generator_id", "band_id", "resolved_parameters", "correct_answer"]:
		if not _values_equal(question.get(key), event.get(key)):
			return false
	return int(question.get("seed", -1)) == int(event.get("question_seed", -2))

func _projection_matches_event(projection: Dictionary, event: Dictionary) -> bool:
	for key in ["submitted_answer", "correct_answer", "correctness", "response_duration_ms", "hints", "health_delta", "combo", "reward_delta"]:
		if not _values_equal(projection.get(key), event.get(key)):
			return false
	return true

func _completion_matches_state(event: Dictionary, state: Dictionary) -> bool:
	return (
		state.get("status") == "completed"
		and event.get("completion_reason") == state.get("completion_reason")
		and int(event.get("final_score", -1)) == int(state.get("score", -2))
		and int(event.get("final_health", -1)) == int(state.get("health", -2))
		and _values_equal(event.get("earned_rewards"), state.get("earned_rewards"))
	)

func _activity_matches_state(activity: Dictionary, state: Dictionary) -> bool:
	return (
		not activity.is_empty()
		and state.get("activity_id") == activity.get("activity_id")
		and state.get("content_version") == activity.get("content_version")
	)

func _is_session_interface(session: Variant) -> bool:
	if session == null or not session is Object:
		return false
	for method in ["snapshot", "session_id"]:
		if not session.has_method(method):
			return false
	return session.has_signal("run_completed")

func _clear_active_run() -> void:
	if _active_session != null and _active_session is Object and is_instance_valid(_active_session):
		var completion_callable := Callable(self, "_on_run_completed")
		if _active_session.has_signal("run_completed") and _active_session.run_completed.is_connected(completion_callable):
			_active_session.run_completed.disconnect(completion_callable)
	_active_session = null
	_active_activity = {}

func _values_equal(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return is_finite(float(left)) and is_finite(float(right)) and float(left) == float(right)
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
