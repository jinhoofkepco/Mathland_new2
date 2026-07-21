class_name CountingGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["count_min", "count_max"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var minimum: Variant = parameters.get("count_min")
	var maximum: Variant = parameters.get("count_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(minimum) < 1
		or int(maximum) < int(minimum)
		or int(maximum) > MAX_STATE_ITEMS
	):
		issues.append("COUNT_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("COUNT_RANGE_WIDTH")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var count: int = rng.range_int(parameters["count_min"], parameters["count_max"])
	var item_ids := _indices(count)
	return _foundation_fields(
		{
			"count": count,
			"item_ids": item_ids,
			"manipulative_id": "counters",
			"initial_occupied": item_ids.duplicate(),
		},
		"question.counting",
		{},
		count
	)
