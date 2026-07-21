class_name ProfileActivationService
extends RefCounted

const EventJournalScript = preload("res://src/persistence/event_journal.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")
const ProfileRecordScript = preload("res://src/profiles/profile_record.gd")
const UuidV4Script = preload("res://src/core/uuid_v4.gd")

var _device_id := ""
var _audio_service: Variant
var _effects_service: Variant
var _ui_policy: Variant
var _journal_factory: Callable
var _progress_factory: Callable
var _journal_path_builder: Callable
var _active_settings: Dictionary = ProfileRecordScript.DEFAULT_SETTINGS.duplicate(true)

func _init(
	device_id: String,
	audio_service: Variant,
	effects_service: Variant,
	ui_policy: Variant,
	journal_factory: Callable = Callable(),
	progress_factory: Callable = Callable(),
	journal_path_builder: Callable = Callable()
) -> void:
	_device_id = device_id
	_audio_service = audio_service
	_effects_service = effects_service
	_ui_policy = ui_policy
	_journal_factory = journal_factory
	_progress_factory = progress_factory
	_journal_path_builder = journal_path_builder

func activate(profile_service: Variant, profile_id: String, pin: String, now_unix: int) -> Dictionary:
	if profile_service == null or not profile_service.has_method("verify_and_select"):
		return {"ok": false, "error": "activation_unavailable"}
	if not UuidV4Script.is_valid(_device_id):
		return {"ok": false, "error": "device_identity_unavailable"}
	var previous_profile: Dictionary = profile_service.selected_profile() if profile_service.has_method("selected_profile") else {}
	var previous_profile_id := String(previous_profile.get("profile_id", ""))
	var verified: Variant = profile_service.verify_and_select(profile_id, pin, now_unix)
	if not verified is Dictionary or not verified.get("ok", false):
		return verified.duplicate(true) if verified is Dictionary else {"ok": false, "error": "invalid_activation_result"}
	var profile: Dictionary = verified.get("profile", {}).duplicate(true)
	if profile.get("profile_id", "") != profile_id or not profile.get("settings", null) is Dictionary:
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "invalid_profile", null, false)

	var journal: Variant = _journal_factory.call() if _journal_factory.is_valid() else EventJournalScript.new()
	if journal == null or not journal.has_method("configure") or not journal.has_method("replay"):
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "invalid_journal_factory", null, false)
	var journal_path: Variant = _journal_path_builder.call(profile_id) if _journal_path_builder.is_valid() else "user://profiles/%s/events.jsonl" % profile_id
	if not journal_path is String or String(journal_path).is_empty():
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "invalid_journal_path", null, false)
	var configured: Variant = journal.configure(profile_id, _device_id, journal_path)
	if not configured is Dictionary or not configured.get("ok", false):
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "journal_config_failed", null, false)

	var progress: Variant = _progress_factory.call() if _progress_factory.is_valid() else ProgressServiceScript.new()
	if not progress is Node or not progress.has_method("load_profile") or not progress.has_method("snapshot"):
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "invalid_progress_factory", progress, false)
	var loaded: Variant = progress.load_profile(profile_id, journal)
	if not loaded is Dictionary or not loaded.get("ok", false):
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "progress_load_failed", progress, false)

	var settings: Dictionary = profile.settings.duplicate(true)
	if _audio_service == null or not _audio_service.has_method("apply_settings") or not _audio_service.apply_settings(settings):
		return _fail_after_selection(profile_service, profile_id, previous_profile_id, "audio_apply_failed", progress, true)
	if _effects_service != null:
		if not _effects_service.has_method("set_policy") or not _effects_service.set_policy(StringName(settings.effect_quality), bool(settings.reduced_motion)):
			return _fail_after_selection(profile_service, profile_id, previous_profile_id, "effects_apply_failed", progress, true)
	if _ui_policy != null and _ui_policy.has_method("set_reduced_motion"):
		_ui_policy.set_reduced_motion(bool(settings.reduced_motion))
	_active_settings = settings.duplicate(true)
	return {
		"ok": true,
		"profile": profile.duplicate(true),
		"journal": journal,
		"progress_service": progress,
		"snapshot": progress.snapshot(),
	}

func _fail_after_selection(
	profile_service: Variant,
	failed_profile_id: String,
	previous_profile_id: String,
	error: String,
	progress: Variant,
	restore_live_services: bool
) -> Dictionary:
	_dispose_candidate(progress)
	if restore_live_services:
		_restore_live_services()
	if (
		not profile_service.has_method("restore_selection_after_failed_activation")
		or profile_service.restore_selection_after_failed_activation(failed_profile_id, previous_profile_id) != OK
	):
		return {"ok": false, "error": "selection_rollback_failed", "cause": error}
	return {"ok": false, "error": error}

func _restore_live_services() -> void:
	if _audio_service != null and _audio_service.has_method("apply_settings"):
		_audio_service.apply_settings(_active_settings)
	if _effects_service != null and _effects_service.has_method("set_policy"):
		_effects_service.set_policy(StringName(_active_settings.effect_quality), bool(_active_settings.reduced_motion))
	if _ui_policy != null and _ui_policy.has_method("set_reduced_motion"):
		_ui_policy.set_reduced_motion(bool(_active_settings.reduced_motion))

func _dispose_candidate(candidate: Variant) -> void:
	if candidate is Object and is_instance_valid(candidate):
		candidate.free()
