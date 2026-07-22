class_name NumberBondGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["whole_min", "whole_max", "show_part"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var minimum: Variant = parameters.get("whole_min")
	var maximum: Variant = parameters.get("whole_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(minimum) < 2
		or int(maximum) < int(minimum)
		or int(maximum) > MAX_STATE_ITEMS
	):
		issues.append("WHOLE_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("WHOLE_RANGE_WIDTH")
	if parameters.get("show_part") not in ["left", "right", "random"]:
		issues.append("SHOW_PART")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var whole: int = rng.range_int(parameters["whole_min"], parameters["whole_max"])
	var left_part: int = rng.range_int(0, whole)
	var right_part := whole - left_part
	var shown_side: String = parameters["show_part"]
	if shown_side == "random":
		shown_side = "left" if rng.range_int(0, 1) == 0 else "right"
	var shown_part := left_part if shown_side == "left" else right_part
	var missing_part := right_part if shown_side == "left" else left_part
	return _foundation_fields(
		{
			"whole": whole,
			"parts": [left_part, right_part],
			"shown_side": shown_side,
			"shown_part": shown_part,
			"missing_part": missing_part,
			"manipulative_id": "counters",
			"initial_occupied": _indices(shown_part),
		},
		"question.number_bonds",
		{"whole": whole, "shown_part": shown_part},
		missing_part
	)
