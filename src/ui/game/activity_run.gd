extends "res://src/ui/shared/child_screen.gd"

signal question_presented(question: Dictionary)
signal presentation_failed(code: String)

const AppRouteScript = preload("res://src/app/app_route.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const LegacyQuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")
const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const AdaptiveBandSelectorScript = preload("res://src/content/adaptive_band_selector.gd")
const ManipulativeFactoryScript = preload("res://src/game/manipulatives/manipulative_factory.gd")
const AnswerInputFactoryScript = preload("res://src/ui/game/answer_input_factory.gd")
const LearningEventV1Script = preload("res://src/events/learning_event_v1.gd")
const SystemClockScript = preload("res://src/core/system_clock.gd")
const TenRodBoardScene = preload("res://scenes/game/manipulatives/ten_rod_board.tscn")
const RewardOverlayScene = preload("res://scenes/game/reward_overlay.tscn")
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_RESPONSE_DURATION_MS := 86_400_000
const DIALOGUE_BY_GENERATOR := {
	"counting_v1": &"moa_tutorial_counting",
	"number_bonds_v1": &"moa_tutorial_number_bonds",
	"ten_frame_v1": &"moa_tutorial_ten_frame",
	"base_ten_v1": &"moa_tutorial_base_ten",
	"number_line_v1": &"moa_tutorial_number_line",
	"basic_operations_v1": &"moa_tutorial_basic_operations",
	"foundation_ten_rods": &"moa_tutorial_base_ten",
}

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
var _manipulative: Control
var _answer_input: Control
var _manipulative_host: VBoxContainer
var _answer_input_host: VBoxContainer
var _prompt_label: Label
var _screen_title: Label
var _heart_label: Label
var _score_label: Label
var _error_label: Label
var _introduction: Control
var _introduction_title: Label
var _introduction_body: Label
var _reward_overlay: Control
var _legacy_mode := true
var _current_band_id := &""

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
	_legacy_mode = not _activity.get("difficulty_bands") is Array
	_apply_profile_runtime_options()
	_update_activity_copy()
	_question_engine = _question_engine if _question_engine != null else (
		LegacyQuestionEngineScript.new() if _legacy_mode else QuestionEngineScript.new()
	)
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
	if not _prepare_question_controls(_question):
		_show_error("unsupported_presentation")
		return
	_connect_run_session_signals()
	var started: Variant = _run_session.start_run(_activity, _question)
	if not started is Dictionary or not started.get("ok", false):
		_show_error(String(started.get("error", "run_start_failed")) if started is Dictionary else "run_start_failed")
		return
	_state = started.state.duplicate(true)
	_started = true
	_present_question(_question, false)
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
	var bands: Variant = _activity.get("bands", []) if _legacy_mode else _activity.get("difficulty_bands", [])
	if not bands is Array or bands.is_empty() or not bands[0] is Dictionary:
		return {}
	var band_id := StringName(bands[0].get("band_id", ""))
	if not _legacy_mode:
		var requested := StringName(_params.get("band_id", String(band_id))) if _current_band_id.is_empty() else _current_band_id
		var selector := AdaptiveBandSelectorScript.new()
		band_id = selector.select(_activity, requested, _recent_events(), _adaptive_enabled())
		_current_band_id = band_id
	var generated: Variant = _question_engine.generate_question(_activity, band_id, seed)
	return generated.duplicate(true) if generated is Dictionary else {}

func _present_question(question: Dictionary, prepare_controls := true) -> void:
	_question = question.duplicate(true)
	if prepare_controls and not _prepare_question_controls(_question):
		_show_error("unsupported_presentation")
		return
	if _prompt_label != null:
		_prompt_label.text = _formatted_prompt(_question)
	_question_presented_at_ms = _now_ms()
	question_presented.emit(_question.duplicate(true))

func _on_board_answer(answer: Variant) -> void:
	submit_answer(answer, _measured_response_ms())

func _on_answer_committed(event: Dictionary, transition: RefCounted) -> void:
	_state = _run_session.snapshot()
	_submitting = false
	var transition_data: Dictionary = transition.to_dict() if transition != null and transition.has_method("to_dict") else {}
	var correctness := bool(event.get("correctness", false))
	if _manipulative != null and _manipulative.has_method("show_feedback"):
		_manipulative.show_feedback(correctness)
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
	if _audio_service != null and _audio_service.has_method("play_sfx"):
		_audio_service.play_sfx(&"correct" if correctness else &"wrong")
	var effect_names: Variant = transition.get("effect_names", [])
	if effect_names is Array:
		for effect_name in effect_names:
			_play_effect(StringName(effect_name), size * 0.5)
	var reward_delta: Variant = event.get("reward_delta", {})
	if reward_delta is Dictionary and int(reward_delta.get("apples", 0)) > 0:
		_show_reward("reward", int(reward_delta.apples))

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

func _show_reward(kind: String, amount: int) -> void:
	if is_instance_valid(_reward_overlay):
		_reward_overlay.queue_free()
	_reward_overlay = RewardOverlayScene.instantiate()
	_reward_overlay.configure({
		"kind": kind,
		"amount": amount,
		"effects_service": _effects_service,
		"ui_policy": _ui_policy,
	})
	_reward_overlay.dismissed.connect(func():
		if is_instance_valid(_reward_overlay):
			_reward_overlay.queue_free()
		_reward_overlay = null
	)
	add_child(_reward_overlay)

func _replay_voice() -> void:
	if _audio_service == null or not _audio_service.has_method("play_voice"):
		return
	var dialogue_id: Variant = DIALOGUE_BY_GENERATOR.get(String(_question.get("generator_id", "")))
	if dialogue_id is StringName:
		_audio_service.play_voice(dialogue_id)

func _build_ui() -> void:
	var ui := MathlandUiScript.scaffold(self, "activity.run.title", "", true)
	_screen_title = ui.title
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
	_prompt_label = MathlandUiScript.literal_label("", 23, MathlandUiScript.INK)
	_prompt_label.name = "QuestionPrompt"
	_prompt_label.custom_minimum_size = Vector2(0, 52)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_prompt_label)
	_manipulative_host = VBoxContainer.new()
	_manipulative_host.name = "ManipulativeHost"
	_manipulative_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_manipulative_host)
	_answer_input_host = VBoxContainer.new()
	_answer_input_host.name = "AnswerInputHost"
	_answer_input_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_answer_input_host)
	_build_introduction()

func _register_tactile_descendants(parent: Node) -> void:
	if _ui_policy == null or not _ui_policy.has_method("register_tactile"):
		return
	for child in parent.get_children():
		if child is Control and child.has_signal("accepted") and "reduced_motion" in child:
			_ui_policy.register_tactile(child)
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
	_introduction_title = MathlandUiScript.label("activity.intro.title", 25, MathlandUiScript.INK)
	_introduction_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_introduction_title)
	_introduction_body = MathlandUiScript.label("activity.intro.body", 17, MathlandUiScript.MUTED_INK)
	_introduction_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_introduction_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_introduction_body)
	var skip := MathlandUiScript.tactile_button("SkipIntroButton", "activity.intro.skip", "arrow_right", Vector2(0, 56), 18)
	column.add_child(skip)
	_connect_tactile(skip, skip_introduction)

func _update_status() -> void:
	if _heart_label != null:
		var health := maxi(0, int(_state.get("health", 0)))
		var initial_health := maxi(health, _configured_initial_health())
		_heart_label.text = "♥".repeat(health) + "♡".repeat(maxi(0, initial_health - health))
	if _score_label != null:
		_score_label.text = TranslationServer.translate("activity.score") % int(_state.get("score", 0))

func _update_interaction() -> void:
	for control in [_manipulative, _answer_input]:
		if control != null and control.has_method("set_interaction_enabled"):
			control.set_interaction_enabled(can_answer())

func _prepare_question_controls(question: Dictionary) -> bool:
	if _manipulative_host == null or _answer_input_host == null:
		return false
	_clear_presentation_controls()
	if _legacy_mode:
		_board = TenRodBoardScene.instantiate()
		_board.name = "TenRodBoard"
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_manipulative_host.add_child(_board)
		_board.configure({"maximum": 99}, question)
		_board.answer_submitted.connect(_on_board_answer)
		_manipulative = _board
		_register_tactile_descendants(_board)
		_manipulative_host.visible = true
		_answer_input_host.visible = false
		return true
	var layout: Variant = question.get("answer_layout")
	var manipulative_data: Variant = question.get("manipulative")
	if not layout is Dictionary or not manipulative_data is Dictionary:
		return false
	var layout_id := StringName(layout.get("id", ""))
	var manipulative_id := StringName(manipulative_data.get("id", ""))
	if not AnswerInputFactoryScript.supports(layout_id) or not ManipulativeFactoryScript.supports(manipulative_id):
		return false
	if layout_id == &"manipulative_submit" and manipulative_id == &"none":
		return false
	if manipulative_id != &"none":
		_manipulative = ManipulativeFactoryScript.create(manipulative_id)
		if _manipulative == null:
			return false
		_manipulative.name = "Manipulative"
		_manipulative.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_manipulative_host.add_child(_manipulative)
		var config: Variant = manipulative_data.get("config", {})
		_manipulative.configure(config if config is Dictionary else {}, question)
		_manipulative.answer_submitted.connect(_on_board_answer)
	if layout_id != &"manipulative_submit":
		_answer_input = AnswerInputFactoryScript.create(layout_id)
		if _answer_input == null:
			_clear_presentation_controls()
			return false
		_answer_input.name = "AnswerInput"
		_answer_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_answer_input_host.add_child(_answer_input)
		_answer_input.configure(question)
		_answer_input.answer_submitted.connect(_on_board_answer)
	_manipulative_host.visible = _manipulative != null
	_answer_input_host.visible = _answer_input != null
	if _manipulative != null:
		_register_tactile_descendants(_manipulative)
	if _answer_input != null:
		_register_tactile_descendants(_answer_input)
	return true

func _clear_presentation_controls() -> void:
	for host in [_manipulative_host, _answer_input_host]:
		if host != null:
			for child in host.get_children():
				host.remove_child(child)
				child.queue_free()
	_board = null
	_manipulative = null
	_answer_input = null

func _apply_profile_runtime_options() -> void:
	if _legacy_mode:
		return
	var settings := _profile_settings()
	if settings.get("timers_enabled", true):
		return
	var run: Variant = _activity.get("run")
	if not run is Dictionary or not run.get("timer") is Dictionary:
		return
	var timer: Dictionary = run.timer
	if timer.get("profile_can_disable", false):
		timer["enabled"] = false
		run["timer"] = timer
		_activity["run"] = run

func _adaptive_enabled() -> bool:
	return bool(_profile_settings().get("adaptive_difficulty", false))

func _profile_settings() -> Dictionary:
	var injected: Variant = _params.get("profile_settings")
	if injected is Dictionary:
		return injected.duplicate(true)
	var profile := _profile()
	var settings: Variant = profile.get("settings", {})
	return settings.duplicate(true) if settings is Dictionary else {}

func _recent_events() -> Array:
	if _journal == null or not _journal.has_method("replay"):
		return []
	var replayed: Variant = _journal.replay()
	if replayed is Dictionary and replayed.get("ok", false) and replayed.get("events") is Array:
		return replayed.events.duplicate(true)
	return []

func _configured_initial_health() -> int:
	var run: Variant = _activity.get("run")
	if run is Dictionary and run.get("starting_hearts") is int:
		return maxi(1, int(run.starting_hearts))
	return maxi(1, int(_activity.get("initial_health", 3)))

func _update_activity_copy() -> void:
	if _screen_title == null or _legacy_mode:
		return
	var localized := _localized_activity()
	var title := String(localized.get("title", ""))
	if not title.is_empty():
		_screen_title.text = title
		_introduction_title.text = title
	var tutorial: Variant = localized.get("tutorial_steps", [])
	if tutorial is Array and not tutorial.is_empty() and tutorial[0] is String:
		_introduction_body.text = tutorial[0]

func _localized_activity() -> Dictionary:
	var localizations: Variant = _activity.get("localizations", {})
	if not localizations is Dictionary:
		return {}
	var locale := TranslationServer.get_locale().replace("_", "-")
	for key in [locale, locale.get_slice("-", 0), "ko-KR"]:
		var value: Variant = localizations.get(key)
		if value is Dictionary:
			return value
	return {}

func _formatted_prompt(question: Dictionary) -> String:
	if _legacy_mode:
		var prompt_key: Variant = question.get("prompt_key", "")
		return tr(prompt_key) if prompt_key is String else ""
	var prompt: Variant = question.get("prompt", {})
	if not prompt is Dictionary:
		return ""
	var key := String(prompt.get("key", ""))
	var result := TranslationServer.translate(key)
	var arguments: Variant = prompt.get("args", {})
	if arguments is Dictionary:
		for argument_name in arguments:
			var replacement := str(arguments[argument_name])
			result = result.replace("{%s}" % argument_name, replacement)
			result = result.replace("%%(%s)s" % argument_name, replacement)
		if result == key and arguments.has("expression"):
			result = str(arguments.expression)
	return result

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
