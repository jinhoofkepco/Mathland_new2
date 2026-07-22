class_name AppRoute
extends RefCounted

const PROFILE_SELECT: StringName = &"profile_select"
const ISLAND: StringName = &"island"
const DAILY_PATH: StringName = &"daily_path"
const FREE_PLAY: StringName = &"free_play"
const ACTIVITY_RUN: StringName = &"activity_run"
const RESULT: StringName = &"result"
const INVENTORY: StringName = &"inventory"
const COLLECTION: StringName = &"collection"
const SETTINGS: StringName = &"settings"

const ALL: Array[StringName] = [
	PROFILE_SELECT,
	ISLAND,
	DAILY_PATH,
	FREE_PLAY,
	ACTIVITY_RUN,
	RESULT,
	INVENTORY,
	COLLECTION,
	SETTINGS,
]

static func is_known(route: StringName) -> bool:
	return route in ALL
