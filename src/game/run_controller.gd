class_name RunController
extends RefCounted

const RunConfigScript = preload("res://src/game/run_config.gd")
const RunStateScript = preload("res://src/game/run_state.gd")
const RunTransitionScript = preload("res://src/game/run_transition.gd")
const RunEventProjectionScript = preload("res://src/game/run_event_projection.gd")
const SystemClockScript = preload("res://src/core/system_clock.gd")
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_PENDING_TRANSITIONS := 8
const RUN_STATE_KEYS := [
	"revision",
	"session_id",
	"activity_id",
	"content_version",
	"stage_id",
	"health",
	"score",
	"combo",
	"question_index",
	"current_question",
	"current_seed",
	"awaiting_answer",
	"boss_state",
	"earned_rewards",
	"paused",
	"timer_enabled",
	"timer_started_at_ms",
	"timer_remaining_ms",
	"completion_reason",
	"status",
]

var _clock: Variant
var _config: Variant
var _state: Dictionary = {}
var _planned_transitions: Dictionary = {}
var _planned_transition_order: Array[int] = []

func _init(clock: Variant = null) -> void:
	_clock = clock if clock != null else SystemClockScript.new()

func start(config: Variant, session_id: String) -> Dictionary:
	if not config is RunConfigScript or not config.is_valid() or session_id.is_empty():
		return {"ok": false, "error": "invalid_config"}
	var copied_config := RunConfigScript.new(config.to_dict())
	if not copied_config.is_valid():
		return {"ok": false, "error": "invalid_config"}
	_config = copied_config
	_state = RunStateScript.initial(_config.to_dict(), session_id)
	_clear_planned_transitions()
	return {"ok": true, "state": snapshot()}

func restore(config: Variant, state: Dictionary) -> Dictionary:
	if not config is RunConfigScript or not config.is_valid():
		return {"ok": false, "error": "invalid_config"}
	var copied_config := RunConfigScript.new(config.to_dict())
	if not copied_config.is_valid() or not _is_restorable_state(state, copied_config):
		return {"ok": false, "error": "invalid_state"}
	_config = copied_config
	_state = state.duplicate(true)
	_clear_planned_transitions()
	return {"ok": true, "state": snapshot()}

func begin_question(question: Dictionary) -> Dictionary:
	if not _can_begin_question() or not _is_valid_question(question):
		return {"ok": false, "error": "invalid_question"}
	var next := _state.duplicate(true)
	next.question_index += 1
	next.current_question = question.duplicate(true)
	next.current_seed = question.seed
	next.awaiting_answer = true
	next.boss_state = next.question_index in _config.boss_question_indices
	next.paused = false
	next.timer_enabled = _config.timer_allowed and _config.timer_duration_ms > 0
	next.timer_started_at_ms = _clock.now_ms() if next.timer_enabled else 0
	next.timer_remaining_ms = _config.timer_duration_ms if next.timer_enabled else 0
	next.revision += 1
	_state = next
	_clear_planned_transitions()
	return {"ok": true, "state": snapshot()}

func plan_answer(answer: Variant, response_ms: int, hints: int = 0) -> Variant:
	if not _can_answer() or not _is_nonnegative_safe_integer(response_ms) or not _is_nonnegative_safe_integer(hints):
		return null
	if _state.timer_enabled and time_remaining_ms() <= 0:
		return null
	var submitted: Variant = _canonical_answer(answer)
	var correct: Variant = _canonical_answer(_state.current_question.correct_answer)
	if submitted == null or correct == null:
		return null
	return _plan_outcome("answer", answer, submitted == correct, response_ms, hints)

func plan_timeout() -> Variant:
	if not _can_answer() or not _state.timer_enabled or _state.paused or time_remaining_ms() > 0:
		return null
	return _plan_outcome("timeout", null, false, _config.timer_duration_ms, 0)

func prepare_commit(transition: Variant) -> Dictionary:
	var validated := _validated_planned_transition(transition)
	if not validated.get("ok", false):
		return validated
	var planned: Dictionary = validated.data
	return {
		"ok": true,
		"event": RunEventProjectionScript.new({
			"kind": planned.kind,
			"submitted_answer": _deep_copy(planned.submitted_answer),
			"correct_answer": _deep_copy(planned.correct_answer),
			"correctness": planned.correctness,
			"response_duration_ms": planned.response_duration_ms,
			"hints": planned.hints,
			"health_delta": planned.health_delta,
			"combo": planned.next_state.combo,
			"reward_delta": planned.reward_delta.duplicate(true),
		})
	}

func discard(transition: Variant) -> bool:
	if not transition is RunTransitionScript:
		return false
	var transition_id: int = transition.get_instance_id()
	if not _planned_transitions.has(transition_id):
		return false
	var record: Dictionary = _planned_transitions[transition_id]
	if record.instance != transition:
		return false
	_retire_planned_transition(transition_id)
	return true

func commit(transition: Variant) -> Dictionary:
	var validated := _validated_planned_transition(transition)
	if not validated.get("ok", false):
		return validated
	var planned: Dictionary = validated.data
	var candidate: Dictionary = planned.next_state.duplicate(true)
	candidate.revision = _state.revision + 1
	_state = candidate
	_clear_planned_transitions()
	return {"ok": true, "state": snapshot()}

func pause() -> bool:
	if not _can_answer() or _state.paused:
		return false
	var next := _state.duplicate(true)
	if next.timer_enabled:
		next.timer_remaining_ms = time_remaining_ms()
	next.paused = true
	next.revision += 1
	_state = next
	_clear_planned_transitions()
	return true

func resume() -> bool:
	if _state.is_empty() or _state.status != "running" or not _state.paused:
		return false
	var next := _state.duplicate(true)
	next.paused = false
	if next.timer_enabled:
		next.timer_started_at_ms = _clock.now_ms()
	next.revision += 1
	_state = next
	_clear_planned_transitions()
	return true

func time_remaining_ms() -> int:
	if _state.is_empty() or not _state.get("timer_enabled", false):
		return 0
	if _state.paused:
		return _state.timer_remaining_ms
	var elapsed: int = maxi(_clock.now_ms() - _state.timer_started_at_ms, 0)
	return maxi(_state.timer_remaining_ms - elapsed, 0)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func _plan_outcome(kind: String, answer: Variant, correctness: bool, response_ms: int, hints: int) -> Variant:
	var next := _state.duplicate(true)
	next.awaiting_answer = false
	var rewards := {}
	var effects: Array[String] = []
	var effect_name := ""
	var follow_up := ""
	if correctness:
		next.score += 1
		next.combo += 1
		rewards = _config.reward_per_correct.duplicate(true)
		if not _add_rewards(next.earned_rewards, rewards):
			return null
		effects.append("correct")
		effect_name = _combo_effect(next.combo)
		if effect_name == "correct":
			effect_name = "correct"
		elif not effect_name in effects:
			effects.append(effect_name)
		if next.boss_state:
			effect_name = "boss"
			effects.append("boss")
	else:
		next.combo = 0
		next.health = maxi(next.health - 1, 0)
		effects.assign(["wrong", "health_loss"])
		effect_name = "wrong"
	if next.health <= 0:
		next.status = "completed"
		next.completion_reason = "health_depleted"
		effects.append("health_depleted")
		follow_up = "health_depleted"
	elif next.score >= _config.target_score:
		next.status = "completed"
		next.completion_reason = "target_reached"
		effects.append("target_reached")
		effects.append("level_up")
		follow_up = "level_up"
		if not next.boss_state:
			effect_name = "target_reached"
	next.timer_remaining_ms = time_remaining_ms()
	var event_answer: Variant = _timeout_answer(_state.current_question.correct_answer) if kind == "timeout" else answer
	var transition := RunTransitionScript.new({
		"from_revision": _state.revision,
		"kind": kind,
		"submitted_answer": event_answer,
		"correct_answer": _state.current_question.correct_answer,
		"correctness": correctness,
		"response_duration_ms": response_ms,
		"hints": hints,
		"health_delta": next.health - _state.health,
		"reward_delta": rewards,
		"effect_name": effect_name,
		"follow_up_effect_name": follow_up,
		"effect_intensity": _config.effect_intensity,
		"effect_names": effects,
		"next_state": next,
	})
	while _planned_transition_order.size() >= MAX_PENDING_TRANSITIONS:
		_retire_planned_transition(_planned_transition_order[0])
	var transition_id: int = transition.get_instance_id()
	_planned_transitions[transition_id] = {
		"instance": transition,
		"data": transition.to_dict(),
	}
	_planned_transition_order.append(transition_id)
	return transition

func _validated_planned_transition(transition: Variant) -> Dictionary:
	if not transition is RunTransitionScript:
		return {"ok": false, "error": "invalid_transition"}
	if _state.is_empty() or transition.from_revision != _state.revision:
		return {"ok": false, "error": "stale_transition"}
	var transition_id: int = transition.get_instance_id()
	if not _planned_transitions.has(transition_id):
		return {"ok": false, "error": "unplanned_transition"}
	var record: Dictionary = _planned_transitions[transition_id]
	if record.instance != transition:
		return {"ok": false, "error": "unplanned_transition"}
	var planned: Dictionary = record.data
	if transition.to_dict() != planned:
		return {"ok": false, "error": "mutated_transition"}
	if not _is_valid_transition_state(planned.next_state):
		return {"ok": false, "error": "invalid_transition"}
	return {"ok": true, "data": planned}

func _retire_planned_transition(transition_id: int) -> void:
	_planned_transitions.erase(transition_id)
	_planned_transition_order.erase(transition_id)

func _clear_planned_transitions() -> void:
	_planned_transitions.clear()
	_planned_transition_order.clear()

func _combo_effect(combo: int) -> String:
	if _config.combo_thresholds.size() >= 2 and combo >= _config.combo_thresholds[1]:
		return "combo_2"
	if _config.combo_thresholds.size() >= 1 and combo >= _config.combo_thresholds[0]:
		return "combo_1"
	return "correct"

func _add_rewards(balance: Dictionary, delta: Dictionary) -> bool:
	for key in delta:
		var current: Variant = balance.get(key, 0)
		if not _is_nonnegative_safe_integer(current) or not _is_nonnegative_safe_integer(delta[key]):
			return false
		if int(current) > MAX_SAFE_INTEGER - int(delta[key]):
			return false
		balance[key] = int(current) + int(delta[key])
	return true

func _can_interact() -> bool:
	return not _state.is_empty() and _state.status == "running" and not _state.paused

func _can_begin_question() -> bool:
	return _can_interact() and not _state.get("awaiting_answer", false)

func _can_answer() -> bool:
	return _can_interact() and _state.get("awaiting_answer", false) and not _state.current_question.is_empty()

func _is_valid_question(question: Dictionary) -> bool:
	return _is_valid_question_for_config(question, _config)

func _is_valid_question_for_config(question: Dictionary, config: Variant) -> bool:
	if config == null:
		return false
	for key in ["question_id", "activity_id", "content_version", "generator_id", "band_id", "seed", "resolved_parameters", "prompt_key", "correct_answer", "answer_layout", "manipulative"]:
		if not question.has(key):
			return false
	if question.activity_id != config.activity_id or question.content_version != config.content_version:
		return false
	if not _is_nonnegative_safe_integer(question.seed):
		return false
	if not question.question_id is String or question.question_id.is_empty():
		return false
	if not question.generator_id is String or question.generator_id.is_empty():
		return false
	if not question.band_id is String or question.band_id.is_empty():
		return false
	if not question.prompt_key is String or question.prompt_key.is_empty():
		return false
	if not question.answer_layout is String or question.answer_layout.is_empty():
		return false
	if not _is_resolved_parameters(question.resolved_parameters) or not question.manipulative is Dictionary:
		return false
	return _canonical_answer(question.correct_answer) != null

func _is_restorable_state(state: Dictionary, config: Variant) -> bool:
	if not _has_exact_keys(state, RUN_STATE_KEYS):
		return false
	if (
		not _is_nonnegative_safe_integer(state.revision)
		or not state.session_id is String
		or state.session_id.is_empty()
		or state.activity_id != config.activity_id
		or state.content_version != config.content_version
		or state.stage_id != config.stage_id
		or not state.health is int
		or state.health <= 0
		or state.health > config.initial_health
		or not _is_nonnegative_safe_integer(state.score)
		or state.score >= config.target_score
		or not _is_nonnegative_safe_integer(state.combo)
		or not _is_nonnegative_safe_integer(state.question_index)
		or not state.current_question is Dictionary
		or not _is_valid_question_for_config(state.current_question, config)
		or not _is_nonnegative_safe_integer(state.current_seed)
		or state.current_seed != state.current_question.seed
		or not state.awaiting_answer is bool
		or not state.awaiting_answer
		or not state.boss_state is bool
		or state.boss_state != (state.question_index in config.boss_question_indices)
		or not _is_reward_map(state.earned_rewards)
		or not state.paused is bool
		or not state.timer_enabled is bool
		or (state.timer_enabled and not config.timer_allowed)
		or not _is_nonnegative_safe_integer(state.timer_started_at_ms)
		or not _is_nonnegative_safe_integer(state.timer_remaining_ms)
		or state.timer_remaining_ms > config.timer_duration_ms
		or (not state.timer_enabled and state.timer_remaining_ms != 0)
		or state.completion_reason != ""
		or state.status != "running"
	):
		return false
	return true

func _is_reward_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is String or key.is_empty() or not _is_nonnegative_safe_integer(value[key]):
			return false
	return true

func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

func _is_resolved_parameters(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if not key is String or key.is_empty():
			return false
		var item: Variant = value[key]
		if item is bool or item is String or _is_finite_safe_number(item):
			continue
		if not item is Array:
			return false
		for number in item:
			if not _is_finite_safe_number(number):
				return false
	return true

func _is_finite_safe_number(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER

func _timeout_answer(correct_answer: Variant) -> Variant:
	var canonical: Variant = _canonical_answer(correct_answer)
	if canonical == null:
		return null
	if canonical.kind == "integer":
		var integer_value: int = canonical.value
		return {
			"kind": "integer",
			"value": integer_value - 1 if integer_value == MAX_SAFE_INTEGER else integer_value + 1,
		}
	var values: Array = canonical.values.duplicate()
	if values.is_empty():
		values.append(0)
	else:
		values[0] = values[0] - 1 if values[0] == MAX_SAFE_INTEGER else values[0] + 1
	return {"kind": "integer_list", "values": values, "order_matters": canonical.order_matters}

func _is_valid_transition_state(candidate: Dictionary) -> bool:
	if candidate.get("revision") != _state.revision:
		return false
	for key in ["session_id", "activity_id", "content_version", "stage_id"]:
		if candidate.get(key) != _state.get(key):
			return false
	if not candidate.get("health") is int or candidate.health < 0 or candidate.health > _config.initial_health:
		return false
	if not _is_nonnegative_safe_integer(candidate.get("score")) or not _is_nonnegative_safe_integer(candidate.get("combo")):
		return false
	if not candidate.get("earned_rewards") is Dictionary:
		return false
	if not candidate.get("awaiting_answer") is bool or candidate.awaiting_answer:
		return false
	if candidate.get("status") not in ["running", "completed"]:
		return false
	return true

func _canonical_answer(value: Variant) -> Variant:
	if _is_safe_integer(value):
		return {"kind": "integer", "value": int(value)}
	if not value is Dictionary:
		return null
	var answer: Dictionary = value
	if answer.get("kind") == "integer":
		if answer.size() != 2 or not answer.has("value") or not _is_safe_integer(answer.value):
			return null
		return {"kind": "integer", "value": int(answer.value)}
	if answer.get("kind") == "integer_list":
		if answer.size() != 3 or not answer.has("values") or not answer.has("order_matters"):
			return null
		if not answer.values is Array or not answer.order_matters is bool:
			return null
		var values: Array[int] = []
		for item in answer.values:
			if not _is_safe_integer(item):
				return null
			values.append(int(item))
		if not answer.order_matters:
			values.sort()
		return {"kind": "integer_list", "values": values, "order_matters": answer.order_matters}
	return null

func _is_nonnegative_safe_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and value >= 0

func _is_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
	return value is float and is_finite(value) and value == floor(value) and value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER

func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
