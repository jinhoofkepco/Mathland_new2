extends "res://src/ui/shared/child_screen.gd"

signal question_presented(question: Dictionary)
signal presentation_failed(code: String)

const AppRouteScript = preload("res://src/app/app_route.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const QuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")
const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const SystemClockScript = preload("res://src/core/system_clock.gd")
const TenRodBoardScene = preload("res://scenes/game/manipulatives/ten_rod_board.tscn")
const RewardOverlayScene = preload("res://scenes/game/reward_overlay.tscn")
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_RESPONSE_DURATION_MS := 86_400_000

var _journal: Variant
var _question_engine: Variant
var _run_session: Variant
var _app_lifecycle: Variant
var _response_clock: Variant = SystemClockScript.new()
var _activity: Dictionary = {}
var _question: Dictionary = {}
var _state: Dictionary = {}
var _initial_seed := 42
var _next_seed := 42
var _starting_apples := 0
var _started := false
var _introduction_open := true
var _submitting := false
var _persistence_blocked := false
var _question_presented_at_ms := -1
var _board: Control
var _heart_label: Label
var _score_label: Label
var _error_label: Label
var _introduction: Control
var _reward_overlay: Control

func configure(params: Dictionary) -> void:
	super.configure(params)
	_journal = params.get("journal")
	_question_engine = params.get("question_engine")
	_run_session = params.get("run_session")
	_app_lifecycle = params.get("app_lifecycle")
	var response_clock: Variant = params.get("response_clock")
	if response_clock is Object and response_clock.has_method("now_ms"):
		_response_clock = response_clock
	var seed_value: Variant = params.get("seed", 42)
	_initial_seed = int(seed_value) if seed_value is int and seed_value >= 0 else 42
	_next_seed = _initial_seed

func _ready() -> void:
	_build_ui()
	_start_activity()

func introduction_visible() -> bool:
	return _introduction_open and _introduction != null and _introduction.visible

func skip_introduction() -> void:
	_introduction_open = false
	if _introduction != null:
		_introduction.visible = false
	if _audio_service != null and _audio_service.has_method("stop_voice"):
		_audio_service.stop_voice()
	_update_interaction()

func can_answer() -> bool:
	return (
		_started
		and not _introduction_open
		and not _submitting
		and not _persistence_blocked
		and _state.get("status") == "running"
		and _state.get("awaiting_answer", false)
	)

func submit_answer(answer: Variant, response_ms: int, hints: int = 0) -> Dictionary:
	if not can_answer():
		return {"ok": false, "error": "input_unavailable"}
	_submitting = true
	_update_interaction()
	var result: Variant = _run_session.submit_answer(answer, response_ms, hints)
	if not result is Dictionary:
		_submitting = false
		_persistence_blocked = true
		_update_interaction()
		return {"ok": false, "error": "invalid_session_result"}
	if not result.get("ok", false):
		_submitting = false
		var explicitly_retry_safe: bool = result.get("retry_safe", null) is bool and result.retry_safe
		_persistence_blocked = not explicitly_retry_safe or _session_is_blocked()
		_show_error(String(result.get("error", "persistence_failed")))
		_update_interaction()
	return result.duplicate(false)

func current_question() -> Dictionary:
	return _question.duplicate(true)

func current_state() -> Dictionary:
	return _state.duplicate(true)

func session_id() -> String:
	return _run_session.session_id() if _run_session != null and _run_session.has_method("session_id") else ""

func pinned_content_version() -> String:
	return String(_activity.get("content_version", ""))

func _start_activity() -> void:
	if _content_repository == null or not _content_repository.has_method("get_activity"):
		_show_error("content_unavailable")
		return
	var activity_id := StringName(_params.get("activity_id", "foundation_ten_rods"))
	var requested_version := String(_params.get("content_version", ""))
	var resolved: Variant = _content_repository.get_activity(activity_id, requested_version)
	if not resolved is Dictionary or resolved.is_empty():
		_show_error("content_unavailable")
		return
	_activity = resolved.duplicate(true)
	_question_engine = _question_engine if _question_engine != null else QuestionEngineScript.new()
	if _run_session == null and _journal != null and _progress_service != null:
		_run_session = RunSessionScript.new(null, _journal, _progress_service)
	if _run_session == null:
		_show_error("persistence_unavailable")
		return
	_starting_apples = int(_snapshot().get("apples", 0))
	_persistence_blocked = false
	if bool(_params.get("restored_run", false)):
		_restore_activity_run()
		return
	_question = _generate_question(_next_seed)
	if _question.is_empty():
		_show_error("question_unavailable")
		return
	_connect_run_session_signals()
	var started: Variant = _run_session.start_run(_activity, _question)
	if not started is Dictionary or not started.get("ok", false):
		_show_error(String(started.get("error", "run_start_failed")) if started is Dictionary else "run_start_failed")
		return
	_state = started.state.duplicate(true)
	_started = true
	_present_question(_question)
	_offer_activity_intro_voice()
	_bind_lifecycle()
	_update_status()
	_update_interaction()

func _restore_activity_run() -> void:
	if _run_session == null or not _run_session.has_method("snapshot") or not _run_session.has_method("current_question"):
		_show_error("restore_failed")
		return
	var restored_state: Variant = _run_session.snapshot()
	var restored_question: Variant = _run_session.current_question()
	if (
		not restored_state is Dictionary
		or not restored_question is Dictionary
		or restored_state.get("status") != "running"
		or restored_state.get("activity_id") != _activity.get("activity_id")
		or restored_state.get("content_version") != _activity.get("content_version")
		or restored_question.get("seed") != restored_state.get("current_seed")
	):
		_show_error("restore_failed")
		return
	_connect_run_session_signals()
	_state = restored_state.duplicate(true)
	_question = restored_question.duplicate(true)
	_next_seed = int(_question.seed)
	_initial_seed = int(_params.get("seed", _next_seed))
	_starting_apples = maxi(
		int(_snapshot().get("apples", 0)) - int(_state.get("earned_rewards", {}).get("apples", 0)),
		0
	)
	_started = true
	_introduction_open = false
	if _introduction != null:
		_introduction.visible = false
	_present_question(_question)
	_bind_lifecycle()
	_update_status()
	_update_interaction()

func _connect_run_session_signals() -> void:
	var answer_callable := Callable(self, "_on_answer_committed")
	var completion_callable := Callable(self, "_on_run_completed")
	var failure_callable := Callable(self, "_on_persistence_failed")
	if not _run_session.answer_committed.is_connected(answer_callable):
		_run_session.answer_committed.connect(answer_callable)
	if not _run_session.run_completed.is_connected(completion_callable):
		_run_session.run_completed.connect(completion_callable)
	if not _run_session.persistence_failed.is_connected(failure_callable):
		_run_session.persistence_failed.connect(failure_callable)

func _bind_lifecycle() -> void:
	if _app_lifecycle != null and _app_lifecycle.has_method("bind_active_run"):
		var bound: Variant = _app_lifecycle.bind_active_run(_run_session, _activity)
		if not bound is Dictionary or not bound.get("ok", false):
			_show_error("checkpoint_unavailable")

func _on_back_requested() -> void:
	if _app_lifecycle != null and _app_lifecycle.has_method("flush_and_checkpoint"):
		var checkpointed: Variant = _app_lifecycle.flush_and_checkpoint()
		if not checkpointed is Dictionary or not checkpointed.get("ok", false):
			_show_error("checkpoint_failed")
			return
		if _app_lifecycle.has_method("release_active_run"):
			var released: Variant = _app_lifecycle.release_active_run(_run_session)
			if not released is Dictionary or not released.get("ok", false):
				_show_error("checkpoint_failed")
				return
	call_deferred("_back")

func _generate_question(seed: int) -> Dictionary:
	if _question_engine == null or not _question_engine.has_method("generate_question"):
		return {}
	var bands: Variant = _activity.get("bands", [])
	if not bands is Array or bands.is_empty() or not bands[0] is Dictionary:
		return {}
	var band_id := StringName(bands[0].get("band_id", ""))
	var generated: Variant = _question_engine.generate_question(_activity, band_id, seed)
	return generated.duplicate(true) if generated is Dictionary else {}

func _present_question(question: Dictionary) -> void:
	_question = question.duplicate(true)
	_board.configure({"maximum": 99}, _question)
	_question_presented_at_ms = _now_ms()
	_update_activity_music()
	question_presented.emit(_question.duplicate(true))

func _on_board_answer(answer: Variant) -> void:
	submit_answer(answer, _measured_response_ms())

func _on_answer_committed(event: Dictionary, transition: RefCounted) -> void:
	_state = _run_session.snapshot()
	_submitting = false
	var transition_data: Dictionary = transition.to_dict() if transition != null and transition.has_method("to_dict") else {}
	var correctness := bool(event.get("correctness", false))
	_board.show_feedback(correctness)
	_play_answer_presentation(event, transition_data, correctness)
	_update_status()
	if _state.get("status") == "running":
		_next_seed += 1
		var next_question := _generate_question(_next_seed)
		var begun: Variant = _run_session.begin_question(next_question)
		if begun is Dictionary and begun.get("ok", false):
			_state = begun.state.duplicate(true)
			_present_question(next_question)
		else:
			_show_error("next_question_failed")
	_update_interaction()

func _on_run_completed(event: Dictionary, state: Dictionary) -> void:
	_state = state.duplicate(true)
	_started = false
	_submitting = false
	_update_interaction()
	var progress_snapshot := _snapshot()
	_replace(AppRouteScript.RESULT, {
		"activity_id": _activity.activity_id,
		"content_version": _activity.content_version,
		"source": _params.get("source", "free_play"),
		"seed": _initial_seed,
		"journal": _journal,
		"question_engine": _question_engine,
		"run_session": _run_session,
		"result_state": state.duplicate(true),
		"completion_event": event.duplicate(true),
		"progress_snapshot": progress_snapshot,
		"starting_apples": _starting_apples,
	})

func _on_persistence_failed(code: String) -> void:
	_show_error(code)

func _play_answer_presentation(event: Dictionary, transition: Dictionary, correctness: bool) -> void:
	var effect_names: Variant = transition.get("effect_names", [])
	if _audio_service != null and _audio_service.has_method("play_sfx"):
		_audio_service.play_sfx(_answer_sfx_id(transition, effect_names, correctness))
	if effect_names is Array:
		for effect_name in effect_names:
			_play_effect(StringName(effect_name), size * 0.5)
	var reward_delta: Variant = event.get("reward_delta", {})
	var reward_amount := int(reward_delta.get("apples", 0)) if reward_delta is Dictionary else 0
	if effect_names is Array and "level_up" in effect_names:
		_show_reward("level_up", reward_amount, &"level_up_event")
	elif reward_amount > 0:
		_show_reward("reward", reward_amount, &"reward_event")

func _answer_sfx_id(transition: Dictionary, effect_names: Variant, correctness: bool) -> StringName:
	if not correctness and int(transition.get("health_delta", 0)) < 0:
		return &"heart_loss"
	if effect_names is Array and "boss" in effect_names:
		return &"boss"
	var primary := StringName(transition.get("effect_name", ""))
	if primary in [&"combo_1", &"combo_2", &"combo_3"]:
		return primary
	if effect_names is Array and "level_up" in effect_names:
		return &"level_up"
	return &"correct" if correctness else &"wrong"

func present_persisted_reward_event(event: Dictionary) -> bool:
	if not LearningEventV1Script.validate(event).is_empty() or event.get("profile_id", "") != _profile_id:
		return false
	var kind := ""
	match String(event.get("event_type", "")):
		"collection_unlocked":
			kind = "collection"
		"coupon_earned":
			kind = "coupon"
		_:
			return false
	if not _event_is_durable(event) or not _reward_event_is_reduced(event):
		return false
	_show_reward(kind, 0)
	return true

func _show_reward(kind: String, amount: int, voice_policy: StringName = &"reward_event") -> void:
	if is_instance_valid(_reward_overlay):
		_reward_overlay.queue_free()
	_reward_overlay = RewardOverlayScene.instantiate()
	_reward_overlay.configure({
		"kind": kind,
		"amount": amount,
		"effects_service": _effects_service,
		"ui_policy": _ui_policy,
		"audio_service": _audio_service,
		"voice_autoplay_allowed": _voice_autoplay_allowed(),
		"voice_policy": voice_policy,
	})
	_reward_overlay.dismissed.connect(func():
		if is_instance_valid(_reward_overlay):
			_reward_overlay.queue_free()
		_reward_overlay = null
	)
	add_child(_reward_overlay)

func _replay_voice() -> void:
	if _audio_service == null or not _audio_service.has_method("toggle_voice") or not _audio_service.has_method("dialogue_for_activity"):
		return
	var dialogue_id: Variant = _audio_service.dialogue_for_activity(_activity)
	if dialogue_id is StringName and not dialogue_id.is_empty():
		_audio_service.toggle_voice(dialogue_id)

func _offer_activity_intro_voice() -> void:
	if _audio_service != null and _audio_service.has_method("play_policy_voice"):
		_audio_service.play_policy_voice(&"first_activity_entry", _activity, _voice_autoplay_allowed())

func _update_activity_music() -> void:
	if _audio_service == null or not _audio_service.has_method("play_music"):
		return
	_audio_service.play_music(&"boss_loop" if bool(_state.get("boss_state", false)) else &"concentration_loop")

func _voice_autoplay_allowed() -> bool:
	var value: Variant = _params.get("voice_autoplay_allowed", false)
	return value if value is bool else false

func _build_ui() -> void:
	var ui := MathlandUiScript.scaffold(self, "activity.foundation_ten_rods.title", "", true)
	_connect_tactile(ui.back_button, _on_back_requested)
	var body: VBoxContainer = ui.body
	var status_row := HBoxContainer.new()
	status_row.name = "RunStatusRow"
	status_row.custom_minimum_size = Vector2(0, 52)
	status_row.add_theme_constant_override("separation", 8)
	body.add_child(status_row)
	_heart_label = MathlandUiScript.literal_label("♥♥♥", 22, MathlandUiScript.CORAL)
	_heart_label.name = "HeartLabel"
	_heart_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_heart_label)
	_score_label = MathlandUiScript.literal_label("0", 20, MathlandUiScript.DEEP_TEAL)
	_score_label.name = "ScoreLabel"
	status_row.add_child(_score_label)
	var speaker := MathlandUiScript.tactile_button("SpeakerButton", "activity.speaker", "", Vector2(82, 52), 16)
	status_row.add_child(speaker)
	_connect_tactile(speaker, _replay_voice)
	_error_label = MathlandUiScript.literal_label("", 14, MathlandUiScript.CORAL)
	_error_label.name = "RunErrorLabel"
	_error_label.custom_minimum_size = Vector2(0, 18)
	body.add_child(_error_label)
	_board = TenRodBoardScene.instantiate()
	_board.name = "TenRodBoard"
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_board)
	_board.answer_submitted.connect(_on_board_answer)
	if _audio_service != null and _audio_service.has_method("play_sfx"):
		_board.sfx_requested.connect(func(sfx_id: StringName): _audio_service.play_sfx(sfx_id))
	_register_tactile_descendants(_board)
	_build_introduction()

func _register_tactile_descendants(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control and child.has_signal("accepted") and "reduced_motion" in child:
			if _ui_policy != null and _ui_policy.has_method("register_tactile"):
				_ui_policy.register_tactile(child)
			if _audio_service != null and _audio_service.has_method("play_sfx") and child.has_signal("sfx_requested"):
				child.sfx_requested.connect(func(sfx_id: StringName): _audio_service.play_sfx(sfx_id))
		_register_tactile_descendants(child)

func _build_introduction() -> void:
	_introduction = ColorRect.new()
	_introduction.name = "IntroductionOverlay"
	_introduction.color = Color(0.04, 0.19, 0.22, 0.68)
	_introduction.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_introduction)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 16
	center.offset_right = -16
	_introduction.add_child(center)
	var card := MathlandUiScript.card("IntroductionCard", MathlandUiScript.CREAM, 24)
	card.custom_minimum_size = Vector2(320, 0)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	var title := MathlandUiScript.label("activity.intro.title", 25, MathlandUiScript.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var body := MathlandUiScript.label("activity.intro.body", 17, MathlandUiScript.MUTED_INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(body)
	var skip := MathlandUiScript.tactile_button("SkipIntroButton", "activity.intro.skip", "arrow_right", Vector2(0, 56), 18)
	column.add_child(skip)
	_connect_tactile(skip, skip_introduction)

func _update_status() -> void:
	if _heart_label != null:
		var health := maxi(0, int(_state.get("health", 0)))
		var initial_health := maxi(health, int(_activity.get("initial_health", 3)))
		_heart_label.text = "♥".repeat(health) + "♡".repeat(maxi(0, initial_health - health))
	if _score_label != null:
		_score_label.text = TranslationServer.translate("activity.score") % int(_state.get("score", 0))

func _update_interaction() -> void:
	if _board != null:
		_board.set_interaction_enabled(can_answer())

func _session_is_blocked() -> bool:
	return _run_session != null and _run_session.has_method("is_blocked") and bool(_run_session.is_blocked())

func _now_ms() -> int:
	if _response_clock != null and _response_clock.has_method("now_ms"):
		var value: Variant = _response_clock.now_ms()
		if value is int and value >= 0:
			return value
	return maxi(Time.get_ticks_msec(), 0)

func _measured_response_ms() -> int:
	if _question_presented_at_ms < 0:
		return 1
	return clampi(maxi(_now_ms() - _question_presented_at_ms, 1), 1, MAX_RESPONSE_DURATION_MS)

func _event_is_durable(event: Dictionary) -> bool:
	if _journal == null or not _journal.has_method("replay"):
		return false
	var replayed: Variant = _journal.replay()
	if not replayed is Dictionary or not replayed.get("ok", false) or not replayed.get("events", null) is Array:
		return false
	for persisted_event in replayed.events:
		if persisted_event is Dictionary and _events_equal(persisted_event, event):
			return true
	return false

func _reward_event_is_reduced(event: Dictionary) -> bool:
	var progress := _snapshot()
	var event_sequence: Variant = event.get("sequence")
	var progress_sequence: Variant = progress.get("last_sequence")
	if (
		not _is_safe_integer(event_sequence)
		or event_sequence <= 0
		or not _is_safe_integer(progress_sequence)
		or progress_sequence < 0
		or int(progress_sequence) < int(event_sequence)
	):
		return false
	match String(event.event_type):
		"collection_unlocked":
			return progress.get("collections", null) is Array and event.collection_id in progress.collections
		"coupon_earned":
			return progress.get("coupons", null) is Array and event.coupon_id in progress.coupons
	return false

func _is_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return (
		value is float
		and is_finite(value)
		and value >= -MAX_SAFE_INTEGER
		and value <= MAX_SAFE_INTEGER
		and value == floor(value)
	)

func _events_equal(left: Dictionary, right: Dictionary) -> bool:
	return _event_values_equal(left, right)

func _event_values_equal(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return is_finite(float(left)) and is_finite(float(right)) and float(left) == float(right)
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _event_values_equal(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _event_values_equal(left[index], right[index]):
				return false
		return true
	return left == right

func _show_error(code: String) -> void:
	if _error_label != null:
		var translated := TranslationServer.translate("activity.error.%s" % code)
		_error_label.text = translated if translated != "activity.error.%s" % code else TranslationServer.translate("activity.error.generic")
	presentation_failed.emit(code)
