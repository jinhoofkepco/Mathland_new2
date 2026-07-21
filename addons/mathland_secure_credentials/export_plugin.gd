@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
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
