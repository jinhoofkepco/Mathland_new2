extends "res://tests/support/test_case.gd"

func run(_tree: SceneTree) -> void:
	assert_eq(ProjectSettings.get_setting("application/config/version"), "1.0.0")
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1080)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1920)
	assert_not_null(load("res://scenes/app/app_shell.tscn"), "main scene must load")
