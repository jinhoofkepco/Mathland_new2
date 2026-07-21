@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_configure_android_export_paths()
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(
		_platform: EditorExportPlatform,
		debug: bool,
	) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray([
			"mathland_secure_credentials/bin/%s/secure_credentials-%s.aar" % [
				variant,
				variant,
			],
		])

	func _get_name() -> String:
		return "MathLandSecureCredentials"

func _configure_android_export_paths() -> void:
	var java_home := OS.get_environment("JAVA_HOME").strip_edges()
	var android_sdk := OS.get_environment("ANDROID_SDK_ROOT").strip_edges()
	if android_sdk.is_empty():
		android_sdk = OS.get_environment("ANDROID_HOME").strip_edges()
	if not FileAccess.file_exists(java_home.path_join("bin/java")):
		push_error("JAVA_HOME must point to a complete JDK 17 installation")
		return
	if not FileAccess.file_exists(java_home.path_join("bin/javac")):
		push_error("JAVA_HOME must include javac")
		return
	if not FileAccess.file_exists(android_sdk.path_join("platform-tools/adb")):
		push_error("ANDROID_SDK_ROOT or ANDROID_HOME must contain platform-tools/adb")
		return
	if not FileAccess.file_exists(android_sdk.path_join("platforms/android-35/android.jar")):
		push_error("Android SDK platform 35 is required")
		return
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", java_home)
	settings.set_setting("export/android/android_sdk_path", android_sdk)
