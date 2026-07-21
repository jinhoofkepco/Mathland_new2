class_name TenFrameGenerator
extends "res://src/content/generation/generators/foundation_generator_base.gd"

const KEYS: Array[String] = ["target_min", "target_max", "frame_count"]

func validate_parameters(parameters: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	if not _has_exact_keys(parameters, KEYS):
		issues.append("PARAMETER_KEYS")
	var frame_count: Variant = parameters.get("frame_count")
	if frame_count not in [1, 2]:
		issues.append("FRAME_COUNT")
	var capacity := int(frame_count) * 10 if frame_count in [1, 2] else -1
	var minimum: Variant = parameters.get("target_min")
	var maximum: Variant = parameters.get("target_max")
	if (
		not _is_nonnegative_safe_integer(minimum)
		or not _is_nonnegative_safe_integer(maximum)
		or int(maximum) < int(minimum)
		or int(maximum) > capacity
	):
		issues.append("TARGET_RANGE")
	elif not _is_supported_rng_range(minimum, maximum):
		issues.append("TARGET_RANGE_WIDTH")
	return issues

func generate(_activity: Dictionary, band: Dictionary, seed: int) -> Dictionary:
	var parameters: Variant = _parameters(band)
	if not parameters is Dictionary or not validate_parameters(parameters).is_empty():
		return _invalid()
	var rng: Variant = _rng(seed)
	if rng == null:
		return {}
	var target: int = rng.range_int(parameters["target_min"], parameters["target_max"])
	return _foundation_fields(
		{
			"target": target,
			"frame_count": parameters["frame_count"],
			"occupied_cells": _indices(target),
			"manipulative_id": "ten_frame",
		},
		"question.ten_frame",
		{},
		target
	)
