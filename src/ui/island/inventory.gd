extends "res://src/ui/shared/child_screen.gd"

func _ready() -> void:
	var ui := MathlandUiScript.scaffold(self, "inventory.title", "inventory.subtitle", true)
	_connect_tactile(ui.back_button, _back)
	var body: VBoxContainer = ui.body
	var inventory: Dictionary = _snapshot().get("inventory", {})
	if inventory.is_empty():
		var empty := MathlandUiScript.card("InventoryEmpty", MathlandUiScript.CREAM, 20)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_child(MathlandUiScript.label("inventory.empty", 18, MathlandUiScript.MUTED_INK))
		body.add_child(empty)
		return
	var keys := inventory.keys()
	keys.sort()
	for item_id in keys:
		var card := MathlandUiScript.card("Inventory_%s" % item_id, MathlandUiScript.CREAM, 18)
		card.custom_minimum_size = Vector2(0, 64)
		body.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var item_name := MathlandUiScript.label("inventory.%s" % item_id, 19, MathlandUiScript.INK)
		item_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item_name)
		row.add_child(MathlandUiScript.literal_label("× %d" % int(inventory[item_id]), 22, MathlandUiScript.CORAL))
