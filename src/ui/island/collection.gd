extends "res://src/ui/shared/child_screen.gd"

func _ready() -> void:
	var ui := MathlandUiScript.scaffold(self, "collection.title", "collection.subtitle", true)
	_connect_tactile(ui.back_button, _back)
	var body: VBoxContainer = ui.body
	var entries: Array = _snapshot().get("collections", [])
	if entries.is_empty():
		var empty := MathlandUiScript.card("CollectionEmpty", MathlandUiScript.CREAM, 20)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_child(MathlandUiScript.label("collection.empty", 18, MathlandUiScript.MUTED_INK))
		body.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for entry_id in entries:
		var card := MathlandUiScript.card("Collection_%s" % entry_id, MathlandUiScript.SAND, 20)
		card.custom_minimum_size = Vector2(0, 120)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(column)
		var icon := MathlandUiScript.literal_label("✦", 34, MathlandUiScript.CORAL)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(icon)
		var name_label := MathlandUiScript.label("collection.%s" % entry_id, 17, MathlandUiScript.INK)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(name_label)
