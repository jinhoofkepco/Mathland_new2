class_name SyncRetryPolicy
extends RefCounted

const MIN_DELAY_MS := 2000
const MAX_DELAY_MS := 300000

var _jitter_source: Callable
var _attempt := 0

func _init(jitter_source: Callable = Callable()) -> void:
	_jitter_source = jitter_source

func next_delay_ms(attempt: int) -> int:
	var safe_attempt := clampi(attempt, 0, 30)
	var base_delay := mini(int(round(float(MIN_DELAY_MS) * pow(2.0, safe_attempt))), MAX_DELAY_MS)
	var jitter_factor := 0.0
	if _jitter_source.is_valid():
		var sampled: Variant = _jitter_source.call()
		if sampled is float or sampled is int:
			jitter_factor = clampf(float(sampled), -0.2, 0.25)
	else:
		jitter_factor = randf_range(-0.2, 0.2)
	return clampi(int(round(float(base_delay) * (1.0 + jitter_factor))), MIN_DELAY_MS, MAX_DELAY_MS)

func classify(response: Dictionary) -> StringName:
	var status_code := int(response.get("status", 0))
	if status_code <= 0 or status_code == 408 or status_code == 429 or status_code >= 500:
		return &"retry"
	match status_code:
		401:
			return &"refresh"
		400:
			return &"schema"
		403:
			return &"permission"
	return &"client" if status_code >= 400 else &"success"

func record_failure() -> int:
	var delay := next_delay_ms(_attempt)
	_attempt = mini(_attempt + 1, 30)
	return delay

func record_success() -> void:
	_attempt = 0

func current_attempt() -> int:
	return _attempt

func next_scheduled_delay_ms() -> int:
	return next_delay_ms(_attempt)
