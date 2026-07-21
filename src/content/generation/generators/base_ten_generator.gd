class_name BaseTenGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["value_min", "value_max", "max_place"]
const PLACE_MAXIMUMS := {"ones": 9, "tens": 99, "hundreds": 999}

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var place: Variant = parameters.get("max_place")
	if place not in PLACE_MAXIMUMS:
		issues.append("MAX_PLACE")
	var place_maximum: int = PLACE_MAXIMUMS.get(place, -1)
	var minimum: Variant = parameters.get("value_min")
	var maximum: Variant = parameters.get("value_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(maximum) < int(minimum)
		or int(maximum) > place_maximum
	):
		issues.append("VALUE_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("VALUE_RANGE_WIDTH")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var value: int = rng.range_int(parameters["value_min"], parameters["value_max"])
	@warning_ignore("integer_division")
	var hundreds := value / 100
	@warning_ignore("integer_division")
	var tens := (value / 10) % 10
	var ones := value % 10
	return _foundation_fields(
		{
			"value": value,
			"hundreds": hundreds,
			"tens": tens,
			"ones": ones,
			"place_counts": [hundreds, tens, ones],
			"manipulative_id": "base_ten",
		},
		"question.base_ten",
		{},
		value
	)
