extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const ContentValidatorScript = preload("res://src/content/content_validator.gd")

const VALID_MANIFEST_PATH := "res://tests/content/fixtures/minimal_manifest.json"
const VALID_ACTIVITY_PATH := "res://tests/content/fixtures/minimal_valid_activity.json"
const VALID_FIXTURE_ROOT := "res://tests/content/fixtures"
const INVALID_CACHE_ROOT := "user://content_repository_invalid_cache"
const VALID_CACHE_ROOT := "user://content_repository_valid_cache"
const ATOMIC_CACHE_ROOT := "user://content_repository_atomic_cache"
const FAILED_RELOAD_CACHE_ROOT := "user://content_repository_failed_reload_cache"

func run(_tree: SceneTree) -> void:
	assert_true(ContentValidatorScript.new().parse_json("{}").ok)
	_test_returns_deep_copy_and_pins_requested_version()
	_test_returns_immutable_ordered_summaries()
	_test_rejects_invalid_packages()
	_test_valid_cache_candidate_has_priority()
	_test_one_invalid_cached_package_rejects_the_whole_candidate()
	_test_bad_cache_falls_back_to_bundled_candidate()
	_test_failed_reinitialization_preserves_valid_state()
	_test_rejects_manifest_path_traversal()

func _test_returns_deep_copy_and_pins_requested_version() -> void:
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, "user://missing-content-cache")
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	if not initialized.ok:
		return
	var first: Dictionary = repository.get_activity(&"addition_ones", "1.0.0")
	first["run"]["starting_hearts"] = 99
	first["localizations"]["ko-KR"]["title"] = "변조"
	var second: Dictionary = repository.get_activity(&"addition_ones", "1.0.0")
	assert_eq(second["run"]["starting_hearts"], 3)
	assert_ne(second["localizations"]["ko-KR"]["title"], "변조")
	assert_eq(repository.get_activity(&"addition_ones", "9.9.9"), {})
	assert_eq(repository.get_activity(&"unknown"), {})
	assert_eq(repository.get_active_version(&"addition_ones"), "1.0.0")
	assert_eq(repository.get_manifest_version(), "1.0.0")

func _test_returns_immutable_ordered_summaries() -> void:
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, "user://missing-content-cache")
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	if not initialized.ok:
		return
	var summaries: Array[Dictionary] = repository.list_activities()
	assert_eq(summaries.size(), 11)
	assert_eq(summaries[0].keys(), ["activity_id", "title", "icon_id"])
	assert_eq(summaries[0]["activity_id"], "addition_ones")
	assert_eq(summaries[10]["activity_id"], "foundations_basic_operations")
	summaries[0]["title"] = "변조"
	assert_ne(repository.list_activities()[0]["title"], "변조")

func _test_rejects_invalid_packages() -> void:
	var repository := ContentRepositoryScript.new()
	var valid: Dictionary = _read_json_dictionary(VALID_ACTIVITY_PATH)
	assert_true(repository.validate_package(valid).ok)

	var wrong_checksum := valid.duplicate(true)
	wrong_checksum["checksum"] = "sha256:%s" % "0".repeat(64)
	assert_false(repository.validate_package(wrong_checksum).ok)

	var unknown_activity := valid.duplicate(true)
	unknown_activity["activity_id"] = "unknown_activity"
	assert_false(repository.validate_package(unknown_activity).ok)

	var unsupported_schema := valid.duplicate(true)
	unsupported_schema["schema_version"] = 2
	assert_false(repository.validate_package(unsupported_schema).ok)

	var unknown_field := valid.duplicate(true)
	unknown_field["remote_rules"] = "javascript:alert(1)"
	assert_false(repository.validate_package(unknown_field).ok)

	var unsafe_tuning := valid.duplicate(true)
	unsafe_tuning["difficulty_bands"][0]["generator_parameters"]["source"] = "../escape.json"
	assert_false(repository.validate_package(unsafe_tuning).ok)

func _test_valid_cache_candidate_has_priority() -> void:
	_install_cache(VALID_CACHE_ROOT, "캐시 덧셈 탐험")
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, VALID_CACHE_ROOT)
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	assert_eq(initialized.source, "cache")
	assert_eq(
		repository.get_activity(&"addition_ones")["localizations"]["ko-KR"]["title"],
		"캐시 덧셈 탐험"
	)

func _test_one_invalid_cached_package_rejects_the_whole_candidate() -> void:
	_install_cache(ATOMIC_CACHE_ROOT, "사용되면 안 되는 캐시", "subtraction_ones")
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, ATOMIC_CACHE_ROOT)
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	assert_eq(initialized.source, "bundled")
	assert_ne(
		repository.get_activity(&"addition_ones")["localizations"]["ko-KR"]["title"],
		"사용되면 안 되는 캐시"
	)

func _test_bad_cache_falls_back_to_bundled_candidate() -> void:
	_write_text("%s/active-manifest.json" % INVALID_CACHE_ROOT, "{not valid json")
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, INVALID_CACHE_ROOT)
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	assert_eq(initialized.source, "bundled")
	assert_eq(repository.get_active_version(&"addition_ones"), "1.0.0")
	assert_eq(repository.list_activities().size(), 11)

func _test_failed_reinitialization_preserves_valid_state() -> void:
	var repository := ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(VALID_MANIFEST_PATH, "user://missing-content-cache")
	assert_true(initialized.ok, JSON.stringify(initialized.issues))
	if not initialized.ok:
		return
	_write_text("%s/active-manifest.json" % FAILED_RELOAD_CACHE_ROOT, "{\"schema_version\":2}")
	var failed: Variant = repository.initialize(
		"user://content_repository_missing_bundle.json",
		FAILED_RELOAD_CACHE_ROOT
	)
	assert_false(failed.ok)
	assert_eq(repository.get_manifest_version(), "1.0.0")
	assert_eq(repository.get_activity(&"addition_ones")["run"]["starting_hearts"], 3)

func _test_rejects_manifest_path_traversal() -> void:
	var manifest_source := FileAccess.get_file_as_string(VALID_MANIFEST_PATH)
	manifest_source = manifest_source.replace(
		"content/packages/addition_ones/1.0.0.json",
		"content/packages/../escape.json"
	)
	var path := "user://content_repository_traversal_manifest.json"
	_write_text(path, manifest_source)
	var repository := ContentRepositoryScript.new()
	var result: Variant = repository.initialize(path, "user://missing-content-cache")
	assert_false(result.ok)
	assert_eq(repository.list_activities(), [])

func _read_json_dictionary(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _install_cache(cache_root: String, addition_title: String, corrupt_activity: String = "") -> void:
	var manifest := _read_json_dictionary(VALID_MANIFEST_PATH)
	var validator := ContentValidatorScript.new()
	var entries: Array = manifest["packages"]
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var package := _read_json_dictionary("%s/%s" % [VALID_FIXTURE_ROOT, entry["path"]])
		if package["activity_id"] == "addition_ones":
			package["localizations"]["ko-KR"]["title"] = addition_title
			package["checksum"] = validator.content_checksum(package)
			entry["checksum"] = package["checksum"]
		if package["activity_id"] == corrupt_activity:
			package["run"]["goal"]["target"] = int(package["run"]["goal"]["target"]) + 1
		_write_text(
			"%s/%s" % [cache_root, String(entry["path"]).trim_prefix("content/")],
			JSON.stringify(package)
		)
	_write_text("%s/active-manifest.json" % cache_root, JSON.stringify(manifest))

func _write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file != null:
		file.store_string(contents)
		file.close()
