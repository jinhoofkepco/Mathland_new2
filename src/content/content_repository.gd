class_name ContentRepository
extends RefCounted

func get_activity(_activity_id: StringName, _content_version := "") -> Dictionary:
	return {}

func list_activities() -> Array[Dictionary]:
	return []

func get_active_version(_activity_id: StringName) -> String:
	return ""

func get_manifest_version() -> String:
	return ""
