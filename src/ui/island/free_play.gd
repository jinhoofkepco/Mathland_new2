extends "res://src/ui/shared/child_screen.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const AssetCatalogScript = preload("res://src/presentation/assets/asset_catalog.gd")

var _activities: Array[Dictionary] = []

func _ready() -> void:
	var ui := MathlandUiScript.scaffold(self, "free_play.title", "free_play.subtitle", true)
	_connect_tactile(ui.back_button, _back)
	var body: VBoxContainer = ui.body
	if _content_repository != null and _content_repository.has_method("list_activities"):
		var listed: Variant = _content_repository.list_activities()
		if listed is Array:
			for activity in listed:
				if activity is Dictionary:
					_activities.append(activity.duplicate(true))
	if _activities.is_empty():
		var empty := MathlandUiScript.card("FreePlayEmpty", MathlandUiScript.CREAM, 20)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_child(MathlandUiScript.label("free_play.empty", 18, MathlandUiScript.MUTED_INK))
		body.add_child(empty)
		return
	for index in _activities.size():
		var activity := _activities[index]
		var card := MathlandUiScript.card("ActivityCard_%d" % index, MathlandUiScript.CREAM, 20)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 5)
		card.add_child(column)
		var title := String(activity.get("title", "")).strip_edges()
		var title_label := MathlandUiScript.literal_label(title, 21, MathlandUiScript.INK)
		title_label.name = "ActivityTitle_%d" % index
		column.add_child(title_label)
		var description_text := String(activity.get("description", "")).strip_edges()
		var description := MathlandUiScript.literal_label(description_text, 15, MathlandUiScript.MUTED_INK)
		description.name = "ActivityDescription_%d" % index
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
		var activity_id := StringName(activity.get("activity_id", ""))
		var icon_id := AssetCatalogScript.activity_icon_id(activity_id)
		var icon_name := String(icon_id) if not icon_id.is_empty() else "arrow_right"
		var button := MathlandUiScript.tactile_button("ActivityButton_%d" % index, "button.continue", icon_name, Vector2(0, 54), 17)
		button.configure_display_text(title)
		column.add_child(button)
		_connect_tactile(button, _open_activity.bind(index))

func activities() -> Array[Dictionary]:
	return _activities.duplicate(true)

func _open_activity(index: int) -> void:
	if index < 0 or index >= _activities.size():
		return
	var activity: Dictionary = _activities[index]
	_route(AppRouteScript.ACTIVITY_RUN, {
		"source": "free_play",
		"activity_id": activity.get("activity_id", ""),
		"content_version": activity.get("content_version", ""),
	})
