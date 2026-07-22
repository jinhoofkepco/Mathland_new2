extends "res://tests/support/test_case.gd"

const TestScriptLoaderScript = preload("res://tests/support/test_script_loader.gd")

func run(_tree: SceneTree) -> void:
	var loader := TestScriptLoaderScript.new()
	var unloaded := GDScript.new()
	var rejected: Dictionary = loader.instantiate(unloaded, "res://tests/unit/broken.gd")
	assert_false(rejected.ok)
	assert_eq(rejected.error, "script_not_instantiable")
	var valid: Script = load("res://tests/unit/test_project_contract.gd")
	var accepted: Dictionary = loader.instantiate(valid, "res://tests/unit/test_project_contract.gd")
	assert_true(accepted.ok)
	assert_not_null(accepted.instance)
