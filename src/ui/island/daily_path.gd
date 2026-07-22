extends "res://src/ui/shared/child_screen.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const DailyObjectiveServiceScript = preload("res://src/island/daily_objective_service.gd")

var _objectives: Array[Dictionary] = []

func _ready() -> void:
	_objectives = DailyObjectiveServiceScript.new().objectives(_profile_id, _today())
	var ui := MathlandUiScript.scaffold(self, "daily.title", "daily.subtitle", true)
	var back_button: Control = ui.back_button
	_connect_tactile(back_button, _back)
	var body: VBoxContainer = ui.body
	for index in _objectives.size():
		var card := MathlandUiScript.card("ObjectiveCard_%d" % index, MathlandUiScript.CREAM if index == 0 else MathlandUiScript.MINT, 20)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var marker := MathlandUiScript.literal_label("%d" % (index + 1), 26, MathlandUiScript.CORAL)
		marker.custom_minimum_size = Vector2(34, 48)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(marker)
		var label := MathlandUiScript.label(_objectives[index].label_key, 18, MathlandUiScript.INK)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
	var start := MathlandUiScript.tactile_button("StartFirstObjectiveButton", "daily.first", "arrow_right", Vector2(0, 58), 18)
	body.add_child(start)
	_connect_tactile(start, start_first_objective)

func start_first_objective() -> void:
	if _objectives.is_empty():
		return
	var first: Dictionary = _objectives[0]
	_route(AppRouteScript.ACTIVITY_RUN, {
		"source": "daily",
		"activity_id": first.activity_id,
		"objective_id": first.objective_id,
	})
