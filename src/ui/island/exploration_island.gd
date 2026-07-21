extends "res://src/ui/shared/child_screen.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const DailyObjectiveServiceScript = preload("res://src/island/daily_objective_service.gd")
const AssetCatalogScript = preload("res://src/presentation/assets/asset_catalog.gd")

var _objectives: Array[Dictionary] = []
var _apples := 0
var _pending_review := 0
var _online := false
var _queued := 0
var _sync_service: Variant

func _ready() -> void:
	var snapshot := _snapshot()
	_apples = int(snapshot.get("apples", 0))
	_pending_review = int(snapshot.get("pending_review", 0))
	_sync_service = _params.get("sync_service")
	var sync_status: Variant = _sync_service.status() if _sync_service != null and _sync_service.has_method("status") else {}
	if sync_status is Dictionary and sync_status.has("state"):
		_online = sync_status.get("state") == "online"
		_queued = maxi(0, int(sync_status.get("pending_count", 0)))
	else:
		_online = bool(_params.get("online", false))
		_queued = maxi(0, int(_params.get("sync_queue_count", 0)))
	_objectives = DailyObjectiveServiceScript.new().objectives(_profile_id, _today())
	var ui := MathlandUiScript.scaffold(self, "island.title", "island.subtitle")
	_add_exploration_background()
	var body: VBoxContainer = ui.body
	_add_status_row(body)
	body.add_child(MathlandUiScript.section_label("island.today_objectives"))
	var objective_card := MathlandUiScript.card("DailyObjectives", MathlandUiScript.CREAM, 18)
	body.add_child(objective_card)
	var objective_column := VBoxContainer.new()
	objective_column.add_theme_constant_override("separation", 2)
	objective_card.add_child(objective_column)
	for index in _objectives.size():
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 29)
		row.add_child(MathlandUiScript.literal_label("%d" % (index + 1), 17, MathlandUiScript.CORAL))
		var objective_label := MathlandUiScript.label(_objectives[index].label_key, 16, MathlandUiScript.INK)
		objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(objective_label)
		objective_column.add_child(row)
	var continue_button := MathlandUiScript.tactile_button("ContinueButton", "island.continue", "arrow_right", Vector2(0, 56), 19)
	body.add_child(continue_button)
	_connect_tactile(continue_button, continue_activity)
	var grid := GridContainer.new()
	grid.name = "IslandActions"
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 7)
	body.add_child(grid)
	_add_route_button(grid, "DailyPathButton", "island.daily_path", open_daily_path)
	_add_route_button(grid, "FreePlayButton", "island.free_play", open_free_play)
	_add_route_button(grid, "InventoryButton", "island.inventory", func(): _route(AppRouteScript.INVENTORY))
	_add_route_button(grid, "CollectionButton", "island.collection", func(): _route(AppRouteScript.COLLECTION))
	_add_route_button(grid, "SettingsButton", "island.settings", func(): _route(AppRouteScript.SETTINGS))
	_add_route_button(grid, "SwitchProfileButton", "island.switch_profile", switch_profile)

func objective_keys() -> Array[String]:
	var keys: Array[String] = []
	for objective in _objectives:
		keys.append(objective.objective_id)
	return keys

func apple_balance() -> int:
	return _apples

func pending_review_count() -> int:
	return _pending_review

func sync_state() -> Dictionary:
	return {"online": _online, "queued": _queued}

func open_daily_path() -> void:
	_route(AppRouteScript.DAILY_PATH)

func open_free_play() -> void:
	_route(AppRouteScript.FREE_PLAY)

func switch_profile() -> void:
	_reset_route(AppRouteScript.PROFILE_SELECT, {"profile_id": ""})

func sync_status_text() -> String:
	if _online:
		return TranslationServer.translate("sync.online")
	if _queued <= 0:
		return TranslationServer.translate("sync.offline")
	return TranslationServer.translate("sync.offline_queued") % _queued

func continue_activity() -> void:
	var objective: Dictionary = _objectives[0] if not _objectives.is_empty() else {"activity_id": "foundation_ten_rods", "objective_id": "continue"}
	_route(AppRouteScript.ACTIVITY_RUN, {
		"source": "continue",
		"activity_id": objective.activity_id,
		"objective_id": objective.objective_id,
	})

func _add_exploration_background() -> void:
	var texture := AssetCatalogScript.texture_for(AssetCatalogScript.EXPLORATION_ISLAND_ID)
	if texture == null:
		return
	var background := TextureRect.new()
	background.name = "ExplorationIslandBackground"
	background.texture = texture
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	move_child(background, 1)

func _add_status_row(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "StatusRow"
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var apple := MathlandUiScript.card("AppleBalance", MathlandUiScript.SAND, 14)
	apple.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apple.custom_minimum_size = Vector2(0, 46)
	apple.add_child(MathlandUiScript.literal_label(TranslationServer.translate("island.apples") % _apples, 15, MathlandUiScript.INK))
	row.add_child(apple)
	var review := MathlandUiScript.card("PendingReview", MathlandUiScript.SKY, 14)
	review.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review.custom_minimum_size = Vector2(0, 46)
	review.add_child(MathlandUiScript.literal_label(TranslationServer.translate("island.pending_review") % _pending_review, 15, MathlandUiScript.INK))
	row.add_child(review)
	var sync := MathlandUiScript.card("SyncState", MathlandUiScript.MINT, 14)
	sync.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync.custom_minimum_size = Vector2(0, 46)
	var sync_text := sync_status_text()
	var sync_label := MathlandUiScript.literal_label(sync_text, 13, MathlandUiScript.DEEP_TEAL)
	sync_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sync.add_child(sync_label)
	row.add_child(sync)

func _add_route_button(grid: GridContainer, node_name: String, label_key: String, callback: Callable) -> void:
	var button := MathlandUiScript.tactile_button(node_name, label_key, "", Vector2(0, 52), 16)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(button)
	_connect_tactile(button, callback)
