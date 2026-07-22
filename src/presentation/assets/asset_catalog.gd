class_name AssetCatalog
extends RefCounted

const EXPLORATION_ISLAND_ID: StringName = &"art.island.exploration_bg"
const COLLECTION_SHELLS_ID: StringName = &"art.collection.shells"

const RUNTIME_PATHS := {
	&"art.collection.shells": "res://assets/art/collection/collection_shells.png",
	&"art.island.exploration_bg": "res://assets/art/island/exploration_island_bg.png",
	&"ui.activity.foundations_base_ten": "res://assets/ui/icons/activities/foundations_base_ten.svg",
	&"ui.status.correct": "res://assets/ui/icons/status/correct.svg",
	&"ui.status.heart": "res://assets/ui/icons/status/heart.svg",
	&"ui.status.speaker": "res://assets/ui/icons/status/speaker.svg",
	&"ui.status.wrong": "res://assets/ui/icons/status/wrong.svg",
}

const ACTIVITY_ICON_IDS := {
	&"foundation_ten_rods": &"ui.activity.foundations_base_ten",
}

const COLLECTION_REGIONS := {
	&"first_map": Rect2(64, 304, 480, 480),
}

static func path_for(asset_id: StringName) -> String:
	return String(RUNTIME_PATHS.get(asset_id, ""))

static func texture_for(asset_id: StringName) -> Texture2D:
	var resource_path := path_for(asset_id)
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return null
	return load(resource_path) as Texture2D

static func activity_icon_id(activity_id: StringName) -> StringName:
	return StringName(ACTIVITY_ICON_IDS.get(activity_id, &""))

static func collection_region(entry_id: StringName) -> Rect2:
	return COLLECTION_REGIONS.get(entry_id, Rect2())
