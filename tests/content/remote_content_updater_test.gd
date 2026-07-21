extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const RemoteUpdaterScript = preload("res://src/content/remote_content_updater.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")

const CACHE_ROOT := "user://tests/remote_content"
const MANIFEST_URL := "https://content.mathland.example/active-manifest.json"
const CONTENT_BASE_URL := "https://content.mathland.example/"

func run(_tree: SceneTree) -> void:
	_remove_tree(CACHE_ROOT)
	var repository := ContentRepositoryScript.new()
	assert_true(repository.initialize().ok)
	var pinned_before := repository.get_activity(&"foundations_counting", "1.0.0")
	assert_false(pinned_before.is_empty())
	var first_manifest := _read_json("res://content/active-manifest.json")
	first_manifest["published_at"] = "2026-07-22T00:00:00.000Z"
	var first_transport := FakeTransportScript.new()
	_enqueue_publication(first_transport, first_manifest)
	var updater := RemoteUpdaterScript.new(
		first_transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	var installed: Dictionary = await updater.check_and_install()
	assert_eq(installed.get("status"), "installed", "install failed: %s" % installed)
	assert_true(FileAccess.file_exists("%s/active-manifest.json" % CACHE_ROOT))
	assert_eq(repository.get_activity(&"foundations_counting", "1.0.0"), pinned_before, "active switch invalidated a pinned run")

	var request_count := first_transport.requests.size()
	first_transport.enqueue(_response(first_manifest))
	var up_to_date: Dictionary = await updater.check_and_install()
	assert_eq(up_to_date.get("status"), "up_to_date")
	assert_eq(first_transport.requests.size(), request_count + 1, "up-to-date check downloaded packages")

	var pointer_before := FileAccess.get_file_as_string("%s/active-manifest.json" % CACHE_ROOT)
	var invalid_manifest := first_manifest.duplicate(true)
	invalid_manifest["published_at"] = "2026-07-23T00:00:00.000Z"
	var invalid_transport := FakeTransportScript.new()
	invalid_transport.enqueue(_response(invalid_manifest))
	var first_entry: Dictionary = invalid_manifest.packages[0]
	var invalid_package := _read_json("res://%s" % first_entry.path)
	invalid_package["icon_id"] = "not_allowlisted"
	invalid_transport.enqueue(_response(invalid_package))
	for index in range(1, invalid_manifest.packages.size()):
		var remaining_entry: Dictionary = invalid_manifest.packages[index]
		invalid_transport.enqueue(_response(_read_json("res://%s" % String(remaining_entry.path))))
	var invalid_updater := RemoteUpdaterScript.new(
		invalid_transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	var rejected: Dictionary = await invalid_updater.check_and_install()
	assert_eq(rejected.get("status"), "validation_failed")
	assert_eq(FileAccess.get_file_as_string("%s/active-manifest.json" % CACHE_ROOT), pointer_before)
	assert_eq(repository.get_activity(&"foundations_counting", "1.0.0"), pinned_before)
	_remove_tree(CACHE_ROOT)

func _enqueue_publication(transport: Variant, manifest: Dictionary) -> void:
	transport.enqueue(_response(manifest))
	for entry_value in manifest.packages:
		var entry: Dictionary = entry_value
		transport.enqueue(_response(_read_json("res://%s" % String(entry.path))))

func _response(body: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "body": body.duplicate(true)}

func _read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_remove_contents(absolute)
	DirAccess.remove_absolute(absolute)

func _remove_contents(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_contents(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
