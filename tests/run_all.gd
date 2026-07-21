extends SceneTree

const SUITES := ["unit", "scene", "integration", "content", "manipulatives"]
const TestScriptLoaderScript = preload("res://tests/support/test_script_loader.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite := _selected_suite()
	if suite.is_empty():
		print("RESULT FAIL invalid suite")
		quit(1)
		return

	var test_paths := _discover_tests(suite)
	var failed := false
	var loader := TestScriptLoaderScript.new()
	for path in test_paths:
		var loaded: Variant = load(path)
		var loaded_test: Dictionary = loader.instantiate(loaded, path)
		if not loaded_test.ok:
			failed = true
			print("FAIL %s: %s" % [path, loaded_test.error])
			continue
		var test: Variant = loaded_test.instance
		await test.run(self)
		if test.failures.is_empty():
			print("PASS %s" % path)
		else:
			failed = true
			print("FAIL %s: %s" % [path, "; ".join(test.failures)])

	if failed:
		print("RESULT FAIL tests=%d" % test_paths.size())
		quit(1)
	else:
		print("RESULT PASS tests=%d" % test_paths.size())
		quit(0)

func _selected_suite() -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == "--suite" and index + 1 < arguments.size():
			var suite: String = arguments[index + 1]
			if suite == "all" or suite in SUITES:
				return suite
	return "all"

func _discover_tests(suite: String) -> Array[String]:
	var paths: Array[String] = []
	if suite == "all":
		for suite_name in SUITES:
			paths.append_array(_discover_tests_in("res://tests/%s" % suite_name))
	else:
		paths = _discover_tests_in("res://tests/%s" % suite)
	paths.sort()
	return paths

func _discover_tests_in(directory_path: String) -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return paths

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var path := "%s/%s" % [directory_path, entry]
			if directory.current_is_dir():
				paths.append_array(_discover_tests_in(path))
			elif (
				(entry.begins_with("test_") or entry.ends_with("_test.gd"))
				and entry.ends_with(".gd")
			):
				paths.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return paths
