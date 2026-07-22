class_name CloudSyncService
extends "res://src/sync/sync_service.gd"

const MAX_BATCH_SIZE := 100

var _journal: Variant
var _progress_service: Variant
var _auth: Variant
var _transport: Variant
var _cursor_store: Variant
var _retry_policy: Variant
var _config: Dictionary
var _active := false
var _retry_scheduled := false
var _state := "connecting"
var _last_success_at: Variant = null
var _last_diagnostic := ""
var _known_acknowledged_sequence := 0

func _init(
	journal: Variant,
	progress_service: Variant,
	auth: Variant,
	transport: Variant,
	cursor_store: Variant,
	retry_policy: Variant,
	config: Dictionary
) -> void:
	_journal = journal
	_progress_service = progress_service
	_auth = auth
	_transport = transport
	_cursor_store = cursor_store
	_retry_policy = retry_policy
	_config = config.duplicate(true)
	_hydrate_cursor()

func status() -> Dictionary:
	return {
		"state": _state,
		"pending_count": _pending_count(),
		"last_success_at": _last_success_at,
		"diagnostic": _last_diagnostic,
	}

func request_sync() -> Dictionary:
	if _active or _retry_scheduled:
		return {"ok": true, "scheduled": false, "reason": "already_active"}
	_active = true
	_state = "syncing"
	status_changed.emit(status())
	call_deferred("_run_scheduled_sync")
	return {"ok": true, "scheduled": true}

func sync_until_idle() -> Dictionary:
	if _active:
		return {"ok": false, "error": "sync_in_progress"}
	_active = true
	_state = "syncing"
	var result: Dictionary = await _drain_batches(false)
	_active = false
	status_changed.emit(status())
	return result

func pair_device(code: String, profile_id: String, display_name: String) -> Dictionary:
	if _auth == null or not _auth.has_method("pair"):
		return {"ok": false, "error": "pairing_unavailable"}
	var result: Dictionary = await _auth.pair(code, profile_id, display_name)
	if result.get("ok", false):
		_state = "online"
		_last_diagnostic = ""
		request_sync()
	else:
		_last_diagnostic = String(result.get("error", "pairing_failed"))
		if _last_diagnostic == "re_pair_required":
			_state = "suspended"
		diagnostic.emit(_last_diagnostic)
	status_changed.emit(status())
	return result

func re_pair_device(code: String, profile_id: String, display_name: String) -> Dictionary:
	if _last_diagnostic != "re_pair_required":
		return {"ok": false, "error": "re_pair_not_required"}
	if _auth == null or not _auth.has_method("re_pair"):
		return {"ok": false, "error": "pairing_unavailable"}
	var result: Dictionary = await _auth.re_pair(code, profile_id, display_name)
	if result.get("ok", false):
		_state = "connecting"
		_last_diagnostic = ""
		request_sync()
	else:
		_state = "suspended"
		_last_diagnostic = String(result.get("error", "pairing_failed"))
		diagnostic.emit(_last_diagnostic)
	status_changed.emit(status())
	return result

func _run_scheduled_sync() -> void:
	var _result: Dictionary = await _drain_batches(true)
	_active = false
	status_changed.emit(status())

func _drain_batches(schedule_retries: bool) -> Dictionary:
	if not _dependencies_available():
		return _suspend("sync_dependencies_unavailable")
	var cursor_value: Variant = _cursor_store.load_cursor()
	if not cursor_value is Dictionary:
		return _suspend("invalid_sync_cursor")
	var cursor: Dictionary = cursor_value
	if not String(cursor.get("diagnostic", "")).is_empty():
		return _suspend("invalid_sync_cursor")
	var acknowledged_sequence := maxi(int(cursor.get("acknowledged_sequence", 0)), 0)
	_known_acknowledged_sequence = acknowledged_sequence
	if acknowledged_sequence > 0:
		var recovery_snapshot_error := _snapshot_error(acknowledged_sequence, "")
		if not recovery_snapshot_error.is_empty():
			return _suspend(recovery_snapshot_error)
	var session: Dictionary = await _auth.ensure_session()
	if not session.get("ok", false):
		return _handle_auth_start_failure(session, schedule_retries)
	while true:
		var unread_value: Variant = _journal.unacknowledged(acknowledged_sequence, MAX_BATCH_SIZE)
		if (
			not unread_value is Dictionary
			or unread_value.get("ok") != true
			or not unread_value.get("events", null) is Array
		):
			return _suspend("journal_replay_failed")
		var batch: Array[Dictionary] = []
		for event_value in unread_value.events:
			if not event_value is Dictionary:
				return _suspend("invalid_local_event")
			batch.append(event_value)
		if batch.is_empty():
			_retry_policy.record_success()
			_state = "online"
			_last_diagnostic = ""
			_last_success_at = Time.get_datetime_string_from_system(true)
			return {"ok": true, "acknowledged_sequence": acknowledged_sequence}
		var batch_error := _validate_batch(batch, acknowledged_sequence)
		if not batch_error.is_empty():
			return _suspend(batch_error)
		var response: Dictionary = await _post_batch(batch)
		if int(response.get("status", 0)) == 401:
			var refreshed: Dictionary = await _auth.ensure_session(true)
			if not refreshed.get("ok", false):
				return _suspend(
					"re_pair_required"
					if refreshed.get("error") == "re_pair_required"
					else "authentication"
				)
			response = await _post_batch(batch)
		if not response.get("ok", false):
			var classification: StringName = _retry_policy.classify(response)
			if classification == &"retry":
				return _retry("network", schedule_retries)
			if classification == &"refresh":
				return _suspend("authentication")
			return _suspend(String(classification))
		var acknowledgement := _validated_acknowledgement(batch, response.get("body", {}))
		if not acknowledgement.get("ok", false):
			return _suspend("invalid_acknowledgement")
		var next_sequence := int(acknowledgement.acknowledged_sequence)
		var snapshot_error := _snapshot_error(next_sequence, String(batch[0].profile_id))
		if not snapshot_error.is_empty():
			return _suspend(snapshot_error)
		var cursor_error: Variant = _cursor_store.save_cursor(next_sequence, String(acknowledgement.server_cursor))
		if cursor_error is int and cursor_error != OK:
			return _suspend("cursor_save_failed")
		_known_acknowledged_sequence = next_sequence
		acknowledged_sequence = next_sequence
		_retry_policy.record_success()
	return {"ok": true, "acknowledged_sequence": acknowledged_sequence}

func _post_batch(batch: Array[Dictionary]) -> Dictionary:
	return await _transport.request_json(
		"POST",
		"%s/functions/v1/ingest-events" % String(_config.get("supabase_url", "")).rstrip("/"),
		{
			"Authorization": _auth.authorization_header(),
			"Content-Type": "application/json",
			"apikey": String(_config.get("publishable_key", "")),
		},
		{"events": batch.duplicate(true)}
	)

func _validated_acknowledgement(batch: Array[Dictionary], body_value: Variant) -> Dictionary:
	if not body_value is Dictionary:
		return {"ok": false}
	var body: Dictionary = body_value
	for key in ["accepted_event_ids", "already_present_event_ids", "server_cursor", "request_id"]:
		if not body.has(key):
			return {"ok": false}
	if not body.accepted_event_ids is Array or not body.already_present_event_ids is Array:
		return {"ok": false}
	if not body.server_cursor is String or String(body.server_cursor).is_empty() or not body.request_id is String:
		return {"ok": false}
	var sequence_by_id := {}
	for event in batch:
		sequence_by_id[String(event.event_id)] = int(event.sequence)
	var acknowledged := {}
	for collection_value in [body.accepted_event_ids, body.already_present_event_ids]:
		var collection: Array = collection_value
		for event_id_value in collection:
			if not event_id_value is String or not sequence_by_id.has(event_id_value) or acknowledged.has(event_id_value):
				return {"ok": false}
			acknowledged[event_id_value] = true
	if acknowledged.is_empty():
		return {"ok": false}
	var expected_sequence := int(batch[0].sequence)
	var acknowledged_sequence := expected_sequence - 1
	for event in batch:
		if int(event.sequence) != expected_sequence:
			return {"ok": false}
		if not acknowledged.has(String(event.event_id)):
			break
		acknowledged_sequence = expected_sequence
		expected_sequence += 1
	if acknowledged_sequence < int(batch[0].sequence) or acknowledged.size() != acknowledged_sequence - int(batch[0].sequence) + 1:
		return {"ok": false}
	return {
		"ok": true,
		"acknowledged_sequence": acknowledged_sequence,
		"server_cursor": String(body.server_cursor),
	}

func _validate_batch(batch: Array[Dictionary], after_sequence: int) -> String:
	if batch.size() > MAX_BATCH_SIZE:
		return "oversized_batch"
	var expected_sequence := after_sequence + 1
	var ids := {}
	var profile_id := ""
	var device_id := ""
	for event in batch:
		if not event is Dictionary:
			return "invalid_local_event"
		var event_id := String(event.get("event_id", ""))
		if event_id.is_empty() or ids.has(event_id) or int(event.get("sequence", -1)) != expected_sequence:
			return "invalid_local_event"
		if profile_id.is_empty():
			profile_id = String(event.get("profile_id", ""))
			device_id = String(event.get("device_id", ""))
		if String(event.get("profile_id", "")) != profile_id or String(event.get("device_id", "")) != device_id:
			return "invalid_local_event"
		ids[event_id] = true
		expected_sequence += 1
	return ""

func _dependencies_available() -> bool:
	return (
		_journal != null
		and _journal.has_method("replay")
		and _journal.has_method("unacknowledged")
		and _progress_service != null
		and _progress_service.has_method("snapshot")
		and _auth != null
		and _auth.has_method("ensure_session")
		and _auth.has_method("authorization_header")
		and _transport != null
		and _transport.has_method("request_json")
		and _cursor_store != null
		and _cursor_store.has_method("load_cursor")
		and _cursor_store.has_method("save_cursor")
		and _retry_policy != null
		and _retry_policy.has_method("classify")
	)

func _snapshot_error(required_sequence: int, expected_profile_id: String) -> String:
	var snapshot: Variant = _progress_service.snapshot()
	if not snapshot is Dictionary or snapshot.get("ok", true) == false:
		return "snapshot_failed"
	var profile_id_value: Variant = snapshot.get("profile_id", null)
	if (
		not profile_id_value is String
		or String(profile_id_value).is_empty()
		or (not expected_profile_id.is_empty() and profile_id_value != expected_profile_id)
	):
		return "snapshot_scope_mismatch"
	var last_sequence_value: Variant = snapshot.get("last_sequence", null)
	if not _is_nonnegative_safe_integer(last_sequence_value):
		return "snapshot_failed"
	if int(last_sequence_value) < required_sequence:
		return "snapshot_behind"
	return ""

func _is_nonnegative_safe_integer(value: Variant) -> bool:
	if value is int:
		return value >= 0 and value <= 9007199254740991
	return (
		value is float
		and is_finite(value)
		and value >= 0
		and value <= 9007199254740991
		and value == floor(value)
	)

func _handle_auth_start_failure(result: Dictionary, schedule_retries: bool) -> Dictionary:
	if result.get("error") == "re_pair_required":
		return _suspend("re_pair_required")
	var status_code := int(result.get("status", 0))
	if status_code <= 0 or status_code >= 500:
		return _retry("authentication_network", schedule_retries)
	return _suspend("authentication")

func _retry(code: String, schedule_retry: bool) -> Dictionary:
	var delay_ms := int(_retry_policy.record_failure())
	_state = "retry_wait"
	_last_diagnostic = code
	diagnostic.emit(code)
	if schedule_retry:
		_retry_scheduled = true
		call_deferred("_wait_and_retry", delay_ms)
	return {"ok": false, "error": code, "retry": true, "delay_ms": delay_ms}

func _wait_and_retry(delay_ms: int) -> void:
	var main_loop: Variant = Engine.get_main_loop()
	if main_loop is SceneTree:
		await main_loop.create_timer(float(delay_ms) / 1000.0).timeout
	_retry_scheduled = false
	request_sync()

func _suspend(code: String) -> Dictionary:
	_state = "suspended"
	_last_diagnostic = code
	diagnostic.emit(code)
	return {"ok": false, "error": code}

func _pending_count() -> int:
	if _journal == null or not _journal.has_method("replay"):
		return 0
	var replayed: Variant = _journal.replay()
	if not replayed is Dictionary or not replayed.get("ok", false) or not replayed.get("events", null) is Array:
		return 0
	var count := 0
	for event_value in replayed.events:
		if event_value is Dictionary and int(event_value.get("sequence", -1)) > _known_acknowledged_sequence:
			count += 1
	return count

func _hydrate_cursor() -> void:
	if _journal == null or not _journal.has_method("replay"):
		_state = "offline"
		_last_diagnostic = "sync_dependencies_unavailable"
		return
	var replayed: Variant = _journal.replay()
	if (
		not replayed is Dictionary
		or not replayed.get("ok", false)
		or not replayed.get("events", null) is Array
	):
		_state = "suspended"
		_last_diagnostic = "journal_replay_failed"
		return
	if _cursor_store == null or not _cursor_store.has_method("load_cursor"):
		_state = "offline"
		_last_diagnostic = "sync_dependencies_unavailable"
		return
	var cursor_value: Variant = _cursor_store.load_cursor()
	if not cursor_value is Dictionary:
		_state = "suspended"
		_last_diagnostic = "invalid_sync_cursor"
		return
	var cursor: Dictionary = cursor_value
	if (
		not String(cursor.get("diagnostic", "")).is_empty()
		or not _is_nonnegative_safe_integer(cursor.get("acknowledged_sequence", null))
	):
		_state = "suspended"
		_last_diagnostic = "invalid_sync_cursor"
		return
	_known_acknowledged_sequence = int(cursor.acknowledged_sequence)
