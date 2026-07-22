extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const RemoteUpdaterScript = preload("res://src/content/remote_content_updater.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")

const CACHE_ROOT := "user://tests/remote_content"
const MANIFEST_URL := "https://content.mathland.example/active-manifest.json"
const CONTENT_BASE_URL := "https://content.mathland.example/"

func run(_tree: SceneTree) -> void:
	_remove_tree(CACHE_ROOT)
	_test_version_index_size_is_capped_before_persistence()
	var repository := ContentRepositoryScript.new()
	assert_true(repository.initialize().ok)
	var pinned_before := repository.get_activity(&"foundations_counting", "1.0.0")
	assert_false(pinned_before.is_empty())
	var publication := _publication("1.1.0", "2026-07-22T00:00:00.000Z")
	var first_manifest: Dictionary = publication.manifest
	var first_transport := FakeTransportScript.new()
	_enqueue_publication(first_transport, first_manifest, publication.packages)
	var updater := RemoteUpdaterScript.new(
		first_transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	var installed: Dictionary = await updater.check_and_install()
	assert_eq(installed.get("status"), "installed", "install failed: %s" % installed)
	assert_true(FileAccess.file_exists("%s/active-manifest.json" % CACHE_ROOT))
	assert_true(FileAccess.file_exists("%s/version-index.json" % CACHE_ROOT))
	assert_eq(repository.get_active_version(&"foundations_counting"), "1.1.0")
	assert_eq(repository.get_activity(&"foundations_counting", "1.0.0"), pinned_before, "active switch invalidated a pinned run")
	var restarted_repository := ContentRepositoryScript.new()
	assert_true(restarted_repository.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
	assert_eq(restarted_repository.get_active_version(&"foundations_counting"), "1.1.0")
	assert_eq(
		restarted_repository.get_activity(&"foundations_counting", "1.0.0"),
		pinned_before,
		"restart lost the immutable content version referenced by a checkpoint",
	)

	var request_count := first_transport.requests.size()
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/version-index.json" % CACHE_ROOT)), OK)
	first_transport.enqueue(_response(first_manifest))
	var up_to_date: Dictionary = await updater.check_and_install()
	assert_eq(up_to_date.get("status"), "up_to_date")
	assert_eq(first_transport.requests.size(), request_count + 1, "up-to-date check downloaded packages")
	assert_true(
		FileAccess.file_exists("%s/version-index.json" % CACHE_ROOT),
		"an app upgrade must backfill history for an already-active publication",
	)
	var migrated_restart := ContentRepositoryScript.new()
	assert_true(migrated_restart.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
	assert_eq(migrated_restart.get_activity(&"foundations_counting", "1.0.0"), pinned_before)
	var pinned_middle := migrated_restart.get_activity(&"foundations_counting", "1.1.0")
	assert_false(pinned_middle.is_empty())
	var second_publication := _publication("1.2.0", "2026-07-23T00:00:00.000Z")
	var second_transport := FakeTransportScript.new()
	_enqueue_publication(second_transport, second_publication.manifest, second_publication.packages)
	var second_updater := RemoteUpdaterScript.new(
		second_transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	assert_eq((await second_updater.check_and_install()).get("status"), "installed")
	var second_restart := ContentRepositoryScript.new()
	assert_true(second_restart.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
	assert_eq(second_restart.get_active_version(&"foundations_counting"), "1.2.0")
	assert_eq(second_restart.get_activity(&"foundations_counting", "1.0.0"), pinned_before)
	assert_eq(second_restart.get_activity(&"foundations_counting", "1.1.0"), pinned_middle)

	var pointer_before := FileAccess.get_file_as_string("%s/active-manifest.json" % CACHE_ROOT)
	var invalid_manifest := first_manifest.duplicate(true)
	invalid_manifest["published_at"] = "2026-07-24T00:00:00.000Z"
	var invalid_transport := FakeTransportScript.new()
	invalid_transport.enqueue(_response(invalid_manifest))
	var first_entry: Dictionary = invalid_manifest.packages[0]
	var invalid_packages: Dictionary = publication.packages.duplicate(true)
	var invalid_package: Dictionary = invalid_packages[first_entry.path].duplicate(true)
	invalid_package["icon_id"] = "not_allowlisted"
	invalid_transport.enqueue(_response(invalid_package))
	for index in range(1, invalid_manifest.packages.size()):
		var remaining_entry: Dictionary = invalid_manifest.packages[index]
		invalid_transport.enqueue(_response(invalid_packages[String(remaining_entry.path)]))
	var invalid_updater := RemoteUpdaterScript.new(
		invalid_transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	var rejected: Dictionary = await invalid_updater.check_and_install()
	assert_eq(rejected.get("status"), "validation_failed")
	assert_eq(FileAccess.get_file_as_string("%s/active-manifest.json" % CACHE_ROOT), pointer_before)
	assert_eq(repository.get_activity(&"foundations_counting", "1.0.0"), pinned_before)

	var trusted_index := _read_json("%s/version-index.json" % CACHE_ROOT)
	assert_eq(trusted_index.get("schema_version"), 1)
	assert_true(trusted_index.get("entries") is Array)
	if not trusted_index.get("entries") is Array or trusted_index.entries.is_empty():
		_remove_tree(CACHE_ROOT)
		return
	var pinned_entry := {}
	var replacement_entry := {}
	for entry_value in trusted_index.entries:
		if not entry_value is Dictionary or entry_value.get("content_version") != "1.1.0":
			continue
		if entry_value.get("activity_id") == "foundations_counting":
			pinned_entry = entry_value
		elif replacement_entry.is_empty():
			replacement_entry = entry_value
	assert_false(pinned_entry.is_empty())
	assert_false(replacement_entry.is_empty())
	if not pinned_entry.is_empty() and not replacement_entry.is_empty():
		var pinned_path := "%s/%s" % [CACHE_ROOT, String(pinned_entry.path).trim_prefix("content/")]
		var replacement_path := "%s/%s" % [CACHE_ROOT, String(replacement_entry.path).trim_prefix("content/")]
		var pinned_source := FileAccess.get_file_as_string(pinned_path)
		assert_eq(_write_text(pinned_path, FileAccess.get_file_as_string(replacement_path)), OK)
		var swapped_restart := ContentRepositoryScript.new()
		assert_true(swapped_restart.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
		assert_eq(swapped_restart.get_active_version(&"foundations_counting"), "1.2.0")
		assert_eq(swapped_restart.get_activity(&"foundations_counting", "1.0.0"), {})
		assert_eq(
			swapped_restart.get_activity(&"foundations_counting", "1.1.0"),
			{},
			"a valid package swapped under another indexed identity must invalidate the whole history",
		)
		assert_eq(_write_text(pinned_path, pinned_source), OK)
	var traversal_index := trusted_index.duplicate(true)
	traversal_index.entries[0].path = "content/packages/../stolen.json"
	assert_eq(_write_json("%s/version-index.json" % CACHE_ROOT, traversal_index), OK)
	var traversal_restart := ContentRepositoryScript.new()
	assert_true(traversal_restart.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
	assert_eq(traversal_restart.get_active_version(&"foundations_counting"), "1.2.0")
	assert_eq(
		traversal_restart.get_activity(&"foundations_counting", "1.0.0"),
		{},
		"a partially corrupt history index must fail closed instead of loading untrusted entries",
	)

	assert_eq(_write_json("%s/version-index.json" % CACHE_ROOT, trusted_index), OK)
	assert_eq(_write_text("%s/version-index.json" % CACHE_ROOT, "{broken"), OK)
	var malformed_restart := ContentRepositoryScript.new()
	assert_true(malformed_restart.initialize("res://content/active-manifest.json", CACHE_ROOT).ok)
	assert_eq(malformed_restart.get_activity(&"foundations_counting", "1.0.0"), {})
	assert_true(FileAccess.file_exists("%s/version-index.json.corrupt" % CACHE_ROOT))
	_remove_tree(CACHE_ROOT)
	await _test_semantic_version_reuse_cannot_replace_bundled_history()
	_remove_tree(CACHE_ROOT)

func _test_version_index_size_is_capped_before_persistence() -> void:
	var updater := RemoteUpdaterScript.new(null, null, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT)
	assert_true(updater.has_method("_version_index_document"))
	if not updater.has_method("_version_index_document"):
		return
	var entries := {}
	for index in ContentRepositoryScript.MAX_VERSION_INDEX_ENTRIES + 1:
		entries["activity-%04d@1.0.0" % index] = {
			"activity_id": "activity-%04d" % index,
			"content_version": "1.0.0",
			"checksum": "sha256:%s" % "0".repeat(64),
			"path": "content/packages/activity-%04d/1.0.0.json" % index,
			"source": "cache",
		}
	assert_eq(
		updater.call("_version_index_document", entries),
		{},
		"an oversized index must not be persisted and rejected on the next restart",
	)

func _test_semantic_version_reuse_cannot_replace_bundled_history() -> void:
	var repository := ContentRepositoryScript.new()
	assert_true(repository.initialize().ok)
	var trusted := repository.get_activity(&"foundations_counting", "1.0.0")
	var reused := _publication("1.0.0", "2026-07-24T00:00:00.000Z")
	var entry: Dictionary = reused.manifest.packages[0]
	var changed_package: Dictionary = reused.packages[entry.path].duplicate(true)
	changed_package.localizations["ko-KR"].title += " 변경"
	changed_package.checksum = ContentValidatorScript.new().content_checksum(changed_package)
	reused.packages[entry.path] = changed_package
	reused.manifest.packages[0].checksum = changed_package.checksum
	var transport := FakeTransportScript.new()
	_enqueue_publication(transport, reused.manifest, reused.packages)
	var updater := RemoteUpdaterScript.new(
		transport, repository, MANIFEST_URL, CONTENT_BASE_URL, CACHE_ROOT
	)
	var rejected: Dictionary = await updater.check_and_install()
	assert_false(rejected.get("ok", false), "the same semantic version was activated with different content")
	assert_false(FileAccess.file_exists("%s/active-manifest.json" % CACHE_ROOT))
	assert_eq(repository.get_activity(&"foundations_counting", "1.0.0"), trusted)

func _publication(version: String, published_at: String) -> Dictionary:
	var manifest := _read_json("res://content/active-manifest.json")
	manifest["published_at"] = published_at
	var packages := {}
	var entries: Array[Dictionary] = []
	var validator := ContentValidatorScript.new()
	for old_entry_value in manifest.packages:
		var old_entry: Dictionary = old_entry_value
		var package := _read_json("res://%s" % String(old_entry.path))
		package["content_version"] = version
		package["checksum"] = validator.content_checksum(package)
		var entry := old_entry.duplicate(true)
		entry["content_version"] = version
		entry["path"] = "content/packages/%s/%s.json" % [String(entry.activity_id), version]
		entry["checksum"] = package.checksum
		packages[entry.path] = package
		entries.append(entry)
	manifest["packages"] = entries
	return {"manifest": manifest, "packages": packages}

func _enqueue_publication(transport: Variant, manifest: Dictionary, packages: Dictionary = {}) -> void:
	transport.enqueue(_response(manifest))
	for entry_value in manifest.packages:
		var entry: Dictionary = entry_value
		transport.enqueue(_response(
			packages[String(entry.path)]
			if packages.has(String(entry.path))
			else _read_json("res://%s" % String(entry.path))
		))

func _response(body: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "body": body.duplicate(true)}

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _write_json(path: String, value: Variant) -> Error:
	return _write_text(path, JSON.stringify(value))

func _write_text(path: String, value: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(value)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

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
