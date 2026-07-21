class_name ContentRepository
extends RefCounted

const ValidatorScript = preload("res://src/content/content_validator.gd")
const ValidationResult = preload("res://src/content/content_validation_result.gd")
const Contract = preload("res://src/content/generated/content_contract_v1.gd")

var _validator := ValidatorScript.new()
var _manifest: Dictionary = {}
var _packages: Dictionary = {}
var _active_versions: Dictionary = {}

func initialize(
	bundled_manifest_path := "res://content/active-manifest.json",
	cache_root := "user://content"
) -> ContentValidationResult:
	var rejected_issues: Array[Dictionary] = []
	var cache_manifest_path := _join_path(String(cache_root), "active-manifest.json")
	if FileAccess.file_exists(cache_manifest_path):
		var cache_result := _load_candidate(cache_manifest_path, String(cache_root), "cache")
		if cache_result.ok:
			_commit_candidate(cache_result.value)
			return cache_result
		rejected_issues.append_array(_candidate_issues("cache", cache_result.issues))

	var bundled_result := _load_candidate(String(bundled_manifest_path), "", "bundled")
	if bundled_result.ok:
		_commit_candidate(bundled_result.value)
		return bundled_result
	rejected_issues.append_array(_candidate_issues("bundled", bundled_result.issues))
	return ValidationResult.new(false, rejected_issues)

func validate_package(package: Dictionary) -> ContentValidationResult:
	return _validator.validate_package(package)

func get_activity(activity_id: StringName, content_version := "") -> Dictionary:
	var requested_version := String(content_version)
	var version: String = (
		requested_version
		if not requested_version.is_empty()
		else String(_active_versions.get(String(activity_id), ""))
	)
	if version.is_empty():
		return {}
	var key := "%s@%s" % [String(activity_id), version]
	if not _packages.has(key):
		return {}
	var package_value: Variant = _packages[key]
	return package_value.duplicate(true) if package_value is Dictionary else {}

func list_activities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var activity_order_value: Variant = _manifest.get("activity_order", [])
	if not activity_order_value is Array:
		return result
	for activity_id_value in activity_order_value:
		var activity_id := String(activity_id_value)
		var package := get_activity(StringName(activity_id))
		if package.is_empty():
			continue
		var localizations_value: Variant = package.get("localizations", {})
		var title := ""
		if localizations_value is Dictionary:
			var korean_value: Variant = localizations_value.get("ko-KR", {})
			if korean_value is Dictionary:
				title = String(korean_value.get("title", ""))
		result.append(
			{
				"activity_id": activity_id,
				"title": title,
				"icon_id": String(package.get("icon_id", "")),
			}.duplicate(true)
		)
	return result

func get_active_version(activity_id: StringName) -> String:
	return String(_active_versions.get(String(activity_id), ""))

func get_manifest_version() -> String:
	return String(_manifest.get("manifest_version", ""))

func _load_candidate(manifest_path: String, cache_root: String, source_name: String) -> ContentValidationResult:
	var manifest_read := _read_json_dictionary(manifest_path)
	if not manifest_read.ok:
		return ValidationResult.new(false, manifest_read.issues, null, source_name)
	var manifest: Dictionary = manifest_read.value
	var structure_result := _validator.validate_manifest_structure(manifest)
	if not structure_result.ok:
		return ValidationResult.new(false, structure_result.issues, null, source_name)

	var packages_by_path := {}
	var entries: Array = manifest["packages"]
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var declared_path := String(entry["path"])
		var resolved_path := _resolve_package_path(manifest_path, cache_root, declared_path)
		if resolved_path.is_empty():
			return ValidationResult.new(
				false,
				[_issue("MANIFEST_PACKAGE_PATH", ["packages", index, "path"], "Package path escapes its content root")],
				null,
				source_name
			)
		var package_read := _read_json_dictionary(resolved_path)
		if not package_read.ok:
			var issues := _prefix_issues(["packages", index, "package"], package_read.issues)
			return ValidationResult.new(false, issues, null, source_name)
		packages_by_path[declared_path] = package_read.value

	var validation_result := _validator.validate_manifest(manifest, packages_by_path)
	if not validation_result.ok:
		return ValidationResult.new(false, validation_result.issues, null, source_name)
	var candidate := {
		"manifest": manifest.duplicate(true),
		"packages_by_path": packages_by_path.duplicate(true),
	}
	return ValidationResult.new(true, [], candidate, source_name)

func _read_json_dictionary(path: String) -> ContentValidationResult:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ValidationResult.new(
			false,
			[_issue("FILE_MISSING", [], "Content file could not be opened: %s" % path)],
			null,
			path
		)
	if file.get_length() > Contract.MAX_JSON_SOURCE_BYTES:
		file.close()
		return ValidationResult.new(
			false,
			[_issue("SOURCE_TOO_LARGE", [], "Content file exceeds the pre-read byte limit")],
			null,
			path
		)
	var source := file.get_as_text()
	file.close()
	var parsed := _validator.parse_json(source, path)
	if not parsed.ok:
		return parsed
	if not parsed.value is Dictionary:
		return ValidationResult.new(
			false,
			[_issue("SCHEMA_TYPE", [], "Content document must be a JSON object")],
			null,
			path
		)
	return ValidationResult.new(true, [], parsed.value, path)

func _resolve_package_path(manifest_path: String, cache_root: String, declared_path: String) -> String:
	if not declared_path.begins_with("content/"):
		return ""
	var root: String
	var relative_path: String
	if not cache_root.is_empty():
		root = cache_root.simplify_path()
		relative_path = declared_path.trim_prefix("content/")
	else:
		var manifest_directory := manifest_path.get_base_dir().simplify_path()
		if manifest_directory.get_file() == "content":
			root = manifest_directory
			relative_path = declared_path.trim_prefix("content/")
		else:
			root = manifest_directory
			relative_path = declared_path
	var resolved := _join_path(root, relative_path).simplify_path()
	var required_prefix := "%s/" % root.rstrip("/")
	return resolved if resolved.begins_with(required_prefix) else ""

func _commit_candidate(candidate: Dictionary) -> void:
	var manifest_value: Variant = candidate.get("manifest", {})
	var packages_by_path_value: Variant = candidate.get("packages_by_path", {})
	if not manifest_value is Dictionary or not packages_by_path_value is Dictionary:
		return
	var manifest: Dictionary = manifest_value
	var packages_by_path: Dictionary = packages_by_path_value
	var next_packages := {}
	var next_active_versions := {}
	var entries: Array = manifest["packages"]
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var activity_id := String(entry["activity_id"])
		var version := String(entry["content_version"])
		next_packages["%s@%s" % [activity_id, version]] = packages_by_path[String(entry["path"])].duplicate(true)
		next_active_versions[activity_id] = version
	_manifest = manifest.duplicate(true)
	_packages = next_packages
	_active_versions = next_active_versions

func _join_path(base: String, child: String) -> String:
	return "%s/%s" % [base.rstrip("/"), child.lstrip("/")]

func _candidate_issues(candidate: String, issues: Array[Dictionary]) -> Array[Dictionary]:
	var tagged: Array[Dictionary] = []
	for issue_value in issues:
		var issue: Dictionary = issue_value.duplicate(true)
		issue["candidate"] = candidate
		tagged.append(issue)
	return tagged

func _prefix_issues(prefix: Array, issues: Array[Dictionary]) -> Array[Dictionary]:
	var prefixed: Array[Dictionary] = []
	for issue_value in issues:
		var issue: Dictionary = issue_value.duplicate(true)
		var path: Array = prefix.duplicate()
		path.append_array(issue.get("path", []))
		issue["path"] = path
		prefixed.append(issue)
	return prefixed

func _issue(code: String, path: Array, message: String) -> Dictionary:
	return {"code": code, "path": path.duplicate(), "message": message}
