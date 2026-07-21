class_name RemoteContentUpdater
extends RefCounted

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")

var _transport: Variant
var _repository: Variant
var _manifest_url := ""
var _content_base_url := ""
var _cache_root := ""

static func is_valid_public_config(config: Variant) -> bool:
	if not config is Dictionary:
		return false
	var value: Dictionary = config
	if (
		value.size() != 3
		or not value.get("enabled") is bool
		or not value.get("manifest_url") is String
		or not value.get("content_base_url") is String
	):
		return false
	return (
		_is_safe_public_url(String(value.manifest_url), true)
		and _is_safe_public_url(String(value.content_base_url), false)
	)

func _init(
	transport: Variant,
	repository: Variant,
	manifest_url: String,
	content_base_url: String,
	cache_root: String = "user://content"
) -> void:
	_transport = transport
	_repository = repository
	_manifest_url = manifest_url
	_content_base_url = content_base_url.rstrip("/")
	_cache_root = cache_root.rstrip("/")

func check_and_install() -> Dictionary:
	if not _dependencies_valid():
		return {"ok": false, "status": "configuration_invalid"}
	var manifest_response: Dictionary = await _transport.request_json(
		"GET", _manifest_url, {"Accept": "application/json"}
	)
	if not manifest_response.get("ok", false):
		return {"ok": false, "status": "manifest_network"}
	var manifest_value: Variant = manifest_response.get("body", {})
	if not manifest_value is Dictionary:
		return {"ok": false, "status": "manifest_invalid"}
	var manifest: Dictionary = manifest_value
	if _is_current_publication(manifest):
		return {"ok": true, "status": "up_to_date"}
	var publication_id := _fingerprint(manifest)
	if publication_id.is_empty():
		return {"ok": false, "status": "manifest_invalid"}
	var stage_root := "%s/downloads/%s.tmp" % [_cache_root, publication_id]
	if not _prepare_empty_directory(stage_root):
		return {"ok": false, "status": "cache_unavailable"}
	var entries_value: Variant = manifest.get("packages", null)
	if not entries_value is Array:
		_cleanup_tree(stage_root)
		return {"ok": false, "status": "manifest_invalid"}
	for entry_value in entries_value:
		if not entry_value is Dictionary:
			_cleanup_tree(stage_root)
			return {"ok": false, "status": "manifest_invalid"}
		var entry: Dictionary = entry_value
		var declared_path := String(entry.get("path", ""))
		if not _is_safe_content_path(declared_path):
			_cleanup_tree(stage_root)
			return {"ok": false, "status": "manifest_invalid"}
		var package_response: Dictionary = await _transport.request_json(
			"GET",
			"%s/%s" % [_content_base_url, declared_path],
			{"Accept": "application/json"}
		)
		if not package_response.get("ok", false) or not package_response.get("body", null) is Dictionary:
			_cleanup_tree(stage_root)
			return {"ok": false, "status": "package_network"}
		var relative_path := declared_path.trim_prefix("content/")
		if _write_json("%s/%s" % [stage_root, relative_path], package_response.body) != OK:
			_cleanup_tree(stage_root)
			return {"ok": false, "status": "cache_unavailable"}
	if _write_json("%s/active-manifest.json" % stage_root, manifest) != OK:
		_cleanup_tree(stage_root)
		return {"ok": false, "status": "cache_unavailable"}
	var staged_repository := ContentRepositoryScript.new()
	var staged_validation: Variant = staged_repository.initialize(
		"%s/active-manifest.json" % stage_root, stage_root
	)
	if not staged_validation is Object or not bool(staged_validation.get("ok")):
		_cleanup_tree(stage_root)
		return {
			"ok": false,
			"status": "validation_failed",
			"issues": staged_validation.get("issues") if staged_validation is Object else [],
		}
	if not _promote_packages(stage_root, manifest):
		_cleanup_tree(stage_root)
		return {"ok": false, "status": "cache_unavailable"}
	_cleanup_tree(stage_root)
	var active_manifest := manifest.duplicate(true)
	if not _validate_installed_candidate(active_manifest, publication_id):
		return {"ok": false, "status": "validation_failed"}
	var previous_pointer := _read_json("%s/active-manifest.json" % _cache_root)
	var pointer_store := AtomicJsonStoreScript.new(_cache_root)
	if pointer_store.save("active-manifest.json", active_manifest) != OK:
		return {"ok": false, "status": "cache_unavailable"}
	var activated: Variant = _repository.initialize(
		"res://content/active-manifest.json", _cache_root
	)
	if not activated is Object or not bool(activated.get("ok")):
		_restore_pointer(pointer_store, previous_pointer)
		return {"ok": false, "status": "activation_failed"}
	return {"ok": true, "status": "installed", "publication_id": publication_id}

func _dependencies_valid() -> bool:
	return (
		_transport != null
		and _transport.has_method("request_json")
		and _repository != null
		and _repository.has_method("initialize")
		and is_valid_public_config({
			"enabled": true,
			"manifest_url": _manifest_url,
			"content_base_url": _content_base_url,
		})
		and not _cache_root.is_empty()
	)

static func _is_safe_public_url(url: String, require_json: bool) -> bool:
	if (
		url.is_empty()
		or url.length() > 2048
		or url.contains("@")
		or url.contains("?")
		or url.contains("#")
		or url.contains("\\")
		or url.contains("..")
		or url.to_lower().contains("localhost")
		or url.contains("127.0.0.1")
	):
		return false
	var pattern := RegEx.new()
	var source := (
		"^https://[A-Za-z0-9.-]+(?::[0-9]+)?/[A-Za-z0-9._~/%+-]+\\.json$"
		if require_json
		else "^https://[A-Za-z0-9.-]+(?::[0-9]+)?(?:/[A-Za-z0-9._~/%+-]*)?/?$"
	)
	return pattern.compile(source) == OK and pattern.search(url) != null

func _is_current_publication(manifest: Dictionary) -> bool:
	var current := _read_json("%s/active-manifest.json" % _cache_root)
	return not current.is_empty() and _publication_identity(current) == _publication_identity(manifest)

func _publication_identity(manifest: Dictionary) -> String:
	var packages_value: Variant = manifest.get("packages", [])
	if not packages_value is Array:
		return ""
	var packages: Array[Dictionary] = []
	for entry_value in packages_value:
		if not entry_value is Dictionary:
			return ""
		var entry: Dictionary = entry_value
		packages.append({
			"activity_id": String(entry.get("activity_id", "")),
			"content_version": String(entry.get("content_version", "")),
			"checksum": String(entry.get("checksum", "")),
		})
	return JSON.stringify({
		"manifest_version": manifest.get("manifest_version"),
		"published_at": manifest.get("published_at"),
		"packages": packages,
	})

func _fingerprint(manifest: Dictionary) -> String:
	var identity := _publication_identity(manifest)
	if identity.is_empty():
		return ""
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(identity.to_utf8_buffer())
	return hashing.finish().hex_encode()

func _validate_installed_candidate(manifest: Dictionary, publication_id: String) -> bool:
	var candidate_name := ".active-manifest.%s.candidate.json" % publication_id
	var candidate_path := "%s/%s" % [_cache_root, candidate_name]
	if _write_json(candidate_path, manifest) != OK:
		return false
	var validator := ContentRepositoryScript.new()
	var validation: Variant = validator.call(
		"_load_candidate", candidate_path, _cache_root, "download"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate_path))
	return validation is Object and bool(validation.get("ok"))

func _promote_packages(stage_root: String, manifest: Dictionary) -> bool:
	var entries_value: Variant = manifest.get("packages", null)
	if not entries_value is Array:
		return false
	for entry_value in entries_value:
		if not entry_value is Dictionary:
			return false
		var declared_path := String(entry_value.get("path", ""))
		if not _is_safe_content_path(declared_path):
			return false
		var relative_path := declared_path.trim_prefix("content/")
		var source_path := "%s/%s" % [stage_root, relative_path]
		var target_path := "%s/%s" % [_cache_root, relative_path]
		if FileAccess.file_exists(target_path):
			if _read_json(source_path) != _read_json(target_path):
				return false
			continue
		var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(target_path.get_base_dir())
		)
		if directory_error != OK:
			return false
		var temp_path := "%s.installing" % target_path
		if FileAccess.file_exists(temp_path):
			return false
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		if source_file == null:
			return false
		var bytes := source_file.get_buffer(source_file.get_length())
		var read_error := source_file.get_error()
		source_file.close()
		if read_error != OK:
			return false
		var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
		if temp_file == null:
			return false
		temp_file.store_buffer(bytes)
		temp_file.flush()
		var write_error := temp_file.get_error()
		temp_file.close()
		if write_error != OK:
			return false
		if DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(target_path)
		) != OK:
			return false
	return true

func _prepare_empty_directory(path: String) -> bool:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		_cleanup_tree(path)
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK

func _write_json(path: String, value: Variant) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value))
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _restore_pointer(store: Variant, previous: Dictionary) -> void:
	if not previous.is_empty():
		store.save("active-manifest.json", previous)
		return
	var pointer_path := ProjectSettings.globalize_path("%s/active-manifest.json" % _cache_root)
	if FileAccess.file_exists(pointer_path):
		DirAccess.remove_absolute(pointer_path)

func _is_safe_content_path(path: String) -> bool:
	return (
		path.begins_with("content/")
		and path.ends_with(".json")
		and not path.contains("..")
		and not path.contains("\\")
		and not path.contains(":")
		and path.length() <= 512
	)

func _cleanup_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_cleanup_contents(absolute)
	DirAccess.remove_absolute(absolute)

func _cleanup_contents(absolute: String) -> void:
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := absolute.path_join(entry)
		if directory.current_is_dir():
			_cleanup_contents(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
