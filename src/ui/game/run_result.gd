extends "res://src/ui/shared/child_screen.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")

var _result_state: Dictionary = {}
var _completion_event: Dictionary = {}
var _progress_snapshot: Dictionary = {}
var _starting_apples := 0

func configure(params: Dictionary) -> void:
	super.configure(params)
	_result_state = params.get("result_state", {}).duplicate(true)
	_completion_event = params.get("completion_event", {}).duplicate(true)
	_progress_snapshot = params.get("progress_snapshot", {}).duplicate(true)
	_starting_apples = int(params.get("starting_apples", 0))

func _ready() -> void:
	var ui := MathlandUiScript.scaffold(self, "result.title", "result.subtitle")
	var body: VBoxContainer = ui.body
	var hero := MathlandUiScript.card("ResultHero", MathlandUiScript.SAND, 24)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(hero)
	var hero_column := VBoxContainer.new()
	hero_column.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_column.add_theme_constant_override("separation", 8)
	hero.add_child(hero_column)
	var icon := MathlandUiScript.literal_label("♥" if reason() == "health_depleted" else "★", 48, MathlandUiScript.CORAL)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_column.add_child(icon)
	var reason_label := MathlandUiScript.label("result.reason.%s" % reason(), 23, MathlandUiScript.INK)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_column.add_child(reason_label)
	_add_metric(hero_column, "result.score", int(_result_state.get("score", 0)))
	_add_metric(hero_column, "result.apples", earned_apples())
	_add_metric(hero_column, "result.review", pending_review())
	_add_metric(hero_column, "result.island_delta", int(_progress_snapshot.get("apples", 0)) - _starting_apples)
	var restart_button := MathlandUiScript.tactile_button("RestartButton", "result.restart", "arrow_right", Vector2(0, 58), 19)
	body.add_child(restart_button)
	_connect_tactile(restart_button, restart)
	var island_button := MathlandUiScript.tactile_button("IslandButton", "result.island", "", Vector2(0, 56), 18)
	body.add_child(island_button)
	_connect_tactile(island_button, return_to_island)

func reason() -> String:
	return String(_completion_event.get("completion_reason", _result_state.get("completion_reason", "unknown")))

func earned_apples() -> int:
	return int(_result_state.get("earned_rewards", {}).get("apples", 0))

func pending_review() -> int:
	return int(_progress_snapshot.get("pending_review", 0))

func restart() -> void:
	_replace(AppRouteScript.ACTIVITY_RUN, {
		"activity_id": _params.get("activity_id", "foundation_ten_rods"),
		"content_version": _params.get("content_version", ""),
		"source": _params.get("source", "free_play"),
		"seed": int(_params.get("seed", 42)),
		"journal": _params.get("journal"),
		"question_engine": _params.get("question_engine"),
		"run_session": _params.get("run_session"),
	})

func return_to_island() -> void:
	_route(AppRouteScript.ISLAND)

func _add_metric(parent: VBoxContainer, label_key: String, value: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 38)
	parent.add_child(row)
	var label := MathlandUiScript.label(label_key, 17, MathlandUiScript.MUTED_INK)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(MathlandUiScript.literal_label(str(value), 21, MathlandUiScript.DEEP_TEAL))
