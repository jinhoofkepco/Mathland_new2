extends "res://tests/support/test_case.gd"

const PRESET_NAMES := ["Android Debug", "Android Smoke", "Android Release"]
const REQUIRED_RELEASE_EXCLUDES := [
	"tests/**",
	"docs/**",
	"reports/**",
	"web/**",
	"supabase/**",
	"packages/**",
	"scripts/**",
	"android/plugins/**",
	".env",
	".env.*",
	"dist/**",
]

func run(_tree: SceneTree) -> void:
	_test_project_portrait_compatibility_policy()
	_test_all_android_presets()
	_test_release_excludes_source_but_not_packaged_addon()
	_test_debug_export_bootstraps_editor_paths()

func _test_project_portrait_compatibility_policy() -> void:
	var icon_path: String = ProjectSettings.get_setting("application/config/icon", "")
	assert_eq(icon_path, "res://assets/ui/app/mathland_launcher.svg")
	assert_true(FileAccess.file_exists(icon_path))
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("display/window/handheld/orientation"), 1)
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_true(bool(ProjectSettings.get_setting(
		"rendering/textures/vram_compression/import_etc2_astc",
		false,
	)))

func _test_all_android_presets() -> void:
	var config := ConfigFile.new()
	var load_error := config.load("res://export_presets.cfg")
	assert_eq(load_error, OK, "export_presets.cfg must exist and parse")
	if load_error != OK:
		return
	for index in PRESET_NAMES.size():
		var preset_section := "preset.%d" % index
		var options_section := "%s.options" % preset_section
		assert_eq(config.get_value(preset_section, "name", ""), PRESET_NAMES[index])
		assert_eq(config.get_value(preset_section, "platform", ""), "Android")
		assert_eq(config.get_value(preset_section, "export_filter", ""), "all_resources")
		assert_true(bool(config.get_value(options_section, "gradle_build/use_gradle_build", false)))
		assert_eq(config.get_value(options_section, "gradle_build/gradle_build_directory", ""), "res://android")
		assert_eq(config.get_value(options_section, "gradle_build/min_sdk", ""), "24")
		assert_eq(config.get_value(options_section, "gradle_build/target_sdk", ""), "35")
		assert_true(bool(config.get_value(options_section, "architectures/arm64-v8a", false)))
		assert_false(bool(config.get_value(options_section, "architectures/armeabi-v7a", true)))
		assert_false(bool(config.get_value(options_section, "architectures/x86", true)))
		assert_false(bool(config.get_value(options_section, "architectures/x86_64", true)))
		assert_eq(config.get_value(options_section, "package/unique_name", ""), "com.jinhoofkepco.mathland")
		assert_eq(config.get_value(options_section, "package/name", ""), "MathLand")
		assert_eq(config.get_value(options_section, "version/name", ""), "1.0.0")
		assert_eq(config.get_value(options_section, "version/code", 0), 1)
		assert_true(bool(config.get_value(options_section, "package/signed", false)))
		assert_false(bool(config.get_value(options_section, "package/retain_data_on_uninstall", true)))
		assert_false(bool(config.get_value(options_section, "user_data_backup/allow", true)))
		assert_false(bool(config.get_value(options_section, "graphics/opengl_debug", true)))
		assert_true(bool(config.get_value(options_section, "screen/immersive_mode", false)))
		assert_true(bool(config.get_value(options_section, "permissions/internet", false)))
		assert_true(bool(config.get_value(options_section, "permissions/vibrate", false)))
		assert_eq(config.get_value(options_section, "keystore/release", "not-blank"), "")
		assert_eq(config.get_value(options_section, "keystore/release_user", "not-blank"), "")
		assert_eq(config.get_value(options_section, "keystore/release_password", "not-blank"), "")
		for forbidden_permission in [
			"permissions/camera",
			"permissions/record_audio",
			"permissions/access_fine_location",
			"permissions/read_contacts",
			"permissions/read_external_storage",
			"permissions/write_external_storage",
			"permissions/ad_id",
		]:
			assert_false(bool(config.get_value(options_section, forbidden_permission, false)), forbidden_permission)

func _test_release_excludes_source_but_not_packaged_addon() -> void:
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK:
		return
	var excludes: String = config.get_value("preset.2", "exclude_filter", "")
	var patterns := Array(excludes.split(",", false))
	for required_pattern in REQUIRED_RELEASE_EXCLUDES:
		assert_true(required_pattern in patterns, "Missing release exclusion %s" % required_pattern)
	assert_false("addons/**" in patterns, "Packaged Android AAR must remain exportable")
	assert_eq(config.get_value("preset.2", "export_path", ""), "dist/MathLand-v1.0.0-arm64.apk")

func _test_debug_export_bootstraps_editor_paths() -> void:
	var export_script := FileAccess.get_file_as_string("res://scripts/android/export_debug.sh")
	assert_true(export_script.contains("run verify:toolchain"))
	assert_true(export_script.contains("org.gradle.vfs.watch=false"))
	var plugin_script := FileAccess.get_file_as_string(
		"res://addons/mathland_secure_credentials/export_plugin.gd"
	)
	assert_true(plugin_script.contains("export/android/java_sdk_path"))
	assert_true(plugin_script.contains("export/android/android_sdk_path"))
