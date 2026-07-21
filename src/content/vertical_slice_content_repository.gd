class_name VerticalSliceContentRepository
extends "res://src/content/content_repository.gd"

const CONTENT_PATH := "res://resources/content/foundation_ten_rods.vertical_slice.json"
const ACTIVITY_ID := "foundation_ten_rods"
const CONTENT_VERSION := "a-vertical-1"
const MANIFEST_VERSION := "a-vertical-manifest-1"
const GENERATOR_ID := "foundation_ten_rods"
const MANIPULATIVE_SCENE := "res://scenes/game/manipulatives/ten_rod_board.tscn"

var _activity: Dictionary = {}

func _init() -> void:
	_activity = _load_activity()

func get_activity(activity_id: StringName, content_version := "") -> Dictionary:
	if _activity.is_empty() or String(activity_id) != ACTIVITY_ID:
		return {}
	if not content_version.is_empty() and content_version != CONTENT_VERSION:
		return {}
	return _activity.duplicate(true)

func list_activities() -> Array[Dictionary]:
	if _activity.is_empty():
		return []
	return [_activity.duplicate(true)]

func get_active_version(activity_id: StringName) -> String:
	return CONTENT_VERSION if String(activity_id) == ACTIVITY_ID and not _activity.is_empty() else ""

func get_manifest_version() -> String:
	return MANIFEST_VERSION if not _activity.is_empty() else ""

func _load_activity() -> Dictionary:
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	var candidate: Dictionary = parsed
	if not _is_valid_activity(candidate):
		return {}
	return candidate.duplicate(true)

func _is_valid_activity(candidate: Dictionary) -> bool:
	if candidate.get("schema_version") != 1:
		return false
	if candidate.get("activity_id") != ACTIVITY_ID or candidate.get("content_version") != CONTENT_VERSION:
		return false
	if candidate.get("generator_id") != GENERATOR_ID:
		return false
	if candidate.get("initial_health") != 3 or candidate.get("target_score") != 5:
		return false
	var timer: Variant = candidate.get("timer")
	if not timer is Dictionary or timer.get("enabled") != false or timer.get("duration_ms") != 0:
		return false
	var reward: Variant = candidate.get("reward_per_correct")
	if not reward is Dictionary or reward.get("apples") != 2:
		return false
	var bands: Variant = candidate.get("bands")
	if not bands is Array or bands.size() != 1:
		return false
	var band: Variant = bands[0]
	if not band is Dictionary or band.get("band_id") != "count_to_10":
		return false
	if band.get("minimum") != 1 or band.get("maximum") != 10:
		return false
	if candidate.get("answer_layout") != "numeric_keypad":
		return false
	var manipulative: Variant = candidate.get("manipulative")
	return (
		manipulative is Dictionary
		and manipulative.get("kind") == "ten_rods"
		and manipulative.get("scene_path") == MANIPULATIVE_SCENE
	)
