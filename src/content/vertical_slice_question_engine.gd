class_name VerticalSliceQuestionEngine
extends "res://src/content/question_engine.gd"

const ACTIVITY_ID := "foundation_ten_rods"
const CONTENT_VERSION := "a-vertical-1"
const GENERATOR_ID := "foundation_ten_rods"
const BAND_ID := "count_to_10"
const ALLOWED_MANIPULATIVE_SCENE := "res://scenes/game/manipulatives/ten_rod_board.tscn"
const MAX_SAFE_INTEGER := 9007199254740991

func generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary:
	if seed < 0 or seed > MAX_SAFE_INTEGER or not _is_supported(activity, band_id):
		return {}
	var band: Dictionary = activity.bands[0]
	var minimum: int = band.minimum
	var maximum: int = band.maximum
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var total := random.randi_range(minimum, maximum)
	var left := random.randi_range(0, total)
	var right := total - left
	return {
		"question_id": "%s:%s:%s:%d" % [ACTIVITY_ID, CONTENT_VERSION, BAND_ID, seed],
		"activity_id": ACTIVITY_ID,
		"content_version": CONTENT_VERSION,
		"generator_id": GENERATOR_ID,
		"band_id": BAND_ID,
		"seed": seed,
		"resolved_parameters": {"left": left, "right": right},
		"prompt_key": "activity.foundation_ten_rods.add",
		"correct_answer": total,
		"answer_layout": activity.answer_layout,
		"manipulative": activity.manipulative.duplicate(true),
	}

func _is_supported(activity: Dictionary, band_id: StringName) -> bool:
	if activity.get("activity_id") != ACTIVITY_ID:
		return false
	if activity.get("content_version") != CONTENT_VERSION or activity.get("generator_id") != GENERATOR_ID:
		return false
	if String(band_id) != BAND_ID:
		return false
	var bands: Variant = activity.get("bands")
	if not bands is Array or bands.size() != 1 or not bands[0] is Dictionary:
		return false
	var band: Dictionary = bands[0]
	if band.get("band_id") != BAND_ID or band.get("minimum") != 1 or band.get("maximum") != 10:
		return false
	var manipulative: Variant = activity.get("manipulative")
	return (
		activity.get("answer_layout") == "numeric_keypad"
		and manipulative is Dictionary
		and manipulative.get("kind") == "ten_rods"
		and manipulative.get("scene_path") == ALLOWED_MANIPULATIVE_SCENE
	)
