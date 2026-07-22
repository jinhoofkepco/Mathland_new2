class_name NumberLineGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["axis_min", "axis_max", "step_min", "step_max", "direction"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var axis_minimum: Variant = parameters.get("axis_min")
	var axis_maximum: Variant = parameters.get("axis_max")
	var valid_axis := (
		_is_safe_integer(axis_minimum)
		and _is_safe_integer(axis_maximum)
		and int(axis_maximum) > int(axis_minimum)
		and int(axis_maximum) - int(axis_minimum) <= MAX_STATE_ITEMS - 1
	)
	if not valid_axis:
		issues.append("AXIS_RANGE")
	var step_minimum: Variant = parameters.get("step_min")
	var step_maximum: Variant = parameters.get("step_max")
	if (
		not _is_nonnegative_safe_integer(step_minimum)
		or not _is_nonnegative_safe_integer(step_maximum)
		or int(step_minimum) < 1
		or int(step_maximum) < int(step_minimum)
		or not valid_axis
		or int(step_maximum) > int(axis_maximum) - int(axis_minimum)
	):
		issues.append("STEP_RANGE")
	elif not _is_supported_rng_range(step_minimum, step_maximum):
		issues.append("STEP_RANGE_WIDTH")
	if parameters.get("direction") not in ["forward", "backward", "bidirectional"]:
		issues.append("DIRECTION")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var direction: String = parameters["direction"]
	if direction == "bidirectional":
		direction = "forward" if rng.range_int(0, 1) == 0 else "backward"
	var step_magnitude: int = rng.range_int(parameters["step_min"], parameters["step_max"])
	var is_forward := direction == "forward"
	var start: int
	if is_forward:
		start = rng.range_int(parameters["axis_min"], parameters["axis_max"] - step_magnitude)
	else:
		start = rng.range_int(parameters["axis_min"] + step_magnitude, parameters["axis_max"])
	var signed_step := step_magnitude if is_forward else -step_magnitude
	var endpoint := start + signed_step
	return _foundation_fields(
		{
			"axis_min": parameters["axis_min"],
			"axis_max": parameters["axis_max"],
			"start": start,
			"signed_steps": [signed_step],
			"endpoint": endpoint,
			"direction": direction,
			"visited_ticks": [start],
			"manipulative_id": "number_line",
		},
		"question.number_line",
		{"start": start, "step": signed_step},
		endpoint
	)
