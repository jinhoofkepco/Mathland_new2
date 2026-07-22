extends "res://tests/support/test_case.gd"

const CATALOG_PATH := "res://src/presentation/assets/asset_catalog.gd"

func run(_tree: SceneTree) -> void:
	assert_true(ResourceLoader.exists(CATALOG_PATH), "runtime asset catalog is missing")
	if not ResourceLoader.exists(CATALOG_PATH):
		return
	var CatalogScript: Variant = load(CATALOG_PATH)
	assert_eq(
		CatalogScript.path_for(&"art.island.exploration_bg"),
		"res://assets/art/island/exploration_island_bg.png"
	)
	assert_eq(
		CatalogScript.activity_icon_id(&"foundation_ten_rods"),
		&"ui.activity.foundations_base_ten"
	)
	assert_eq(CatalogScript.activity_icon_id(&"unknown"), &"")
	assert_eq(CatalogScript.path_for(&"unknown"), "")
	assert_eq(CatalogScript.collection_region(&"first_map"), Rect2(64, 304, 480, 480))
	assert_eq(CatalogScript.collection_region(&"unknown"), Rect2())
	var icon: Texture2D = CatalogScript.texture_for(&"ui.status.correct")
	assert_not_null(icon)
	if icon != null:
		assert_eq(icon.resource_path, "res://assets/ui/icons/status/correct.svg")
