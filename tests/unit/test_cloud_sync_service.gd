extends "res://tests/support/test_case.gd"

const CloudSyncScript = preload("res://src/sync/cloud_sync_service.gd")
const RetryPolicyScript = preload("res://src/sync/sync_retry_policy.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")

const CONFIG := {
	"supabase_url": "https://mathland.example.supabase.co",
	"publishable_key": "sb_publishable_test",
}

class FakeJournal extends RefCounted:
	var events: Array[Dictionary] = []
	var operations: Array[String]
	var compact_calls: Array[int] = []
	var replay_error := ""
	var compact_error: Error = OK

	func _init(count: int, shared_operations: Array[String]) -> void:
		operations = shared_operations
		for index in count:
			events.append({
				"event_id": "event-%03d" % (index + 1),
				"profile_id": "profile-1",
				"device_id": "device-1",
				"sequence": index + 1,
			})

	func unacknowledged(after_sequence: int, limit: int = 100) -> Dictionary:
		if not replay_error.is_empty():
			return {"ok": false, "error": replay_error}
		var result: Array[Dictionary] = []
		for event in events:
			if int(event.sequence) > after_sequence and result.size() < limit:
				result.append(event.duplicate(true))
		return {"ok": true, "events": result}

	func replay() -> Dictionary:
		if not replay_error.is_empty():
			return {"ok": false, "error": replay_error}
		return {"ok": true, "events": events.duplicate(true)}

	func compact_through(sequence: int) -> Error:
		operations.append("journal.compact:%d" % sequence)
		compact_calls.append(sequence)
		if compact_error != OK:
			return compact_error
		var retained: Array[Dictionary] = []
		for event in events:
			if int(event.sequence) > sequence:
				retained.append(event)
		events = retained
		return OK

class FakeProgress extends RefCounted:
	var operations: Array[String]
	var fail_snapshot := false
	var snapshot_profile_id := "profile-1"
	var snapshot_last_sequence := 205

	func _init(shared_operations: Array[String]) -> void:
		operations = shared_operations

	func snapshot() -> Dictionary:
		operations.append("progress.snapshot")
		return {"ok": false, "error": "snapshot_failed"} if fail_snapshot else {
			"profile_id": snapshot_profile_id,
			"last_sequence": snapshot_last_sequence,
		}

class FakeAuth extends RefCounted:
	var refresh_calls := 0
	var pair_calls: Array[Dictionary] = []

	func ensure_session(force_refresh: bool = false) -> Dictionary:
		if force_refresh:
			refresh_calls += 1
		return {"ok": true}

	func authorization_header() -> String:
		return "Bearer access-%d" % refresh_calls

	func pair(code: String, profile_id: String, display_name: String) -> Dictionary:
		pair_calls.append({"code": code, "profile_id": profile_id, "display_name": display_name})
		return {"ok": true, "family_id": "family-1", "profile_id": profile_id, "device_id": "device-1"}

class FakeCursorStore extends RefCounted:
	var acknowledged_sequence := 0
	var server_cursor := ""
	var cursor_diagnostic := ""
	var operations: Array[String]

	func _init(shared_operations: Array[String]) -> void:
		operations = shared_operations

	func load_cursor() -> Dictionary:
		var value := {"acknowledged_sequence": acknowledged_sequence, "server_cursor": server_cursor}
		if not cursor_diagnostic.is_empty():
			value["diagnostic"] = cursor_diagnostic
		return value

	func save_cursor(sequence: int, next_server_cursor: String) -> Error:
		operations.append("cursor.save:%d" % sequence)
		acknowledged_sequence = sequence
		server_cursor = next_server_cursor
		return OK

func run(_tree: SceneTree) -> void:
	await _test_batches_205_events_in_order_and_compacts_after_snapshot()
	await _test_duplicate_ids_acknowledge_without_replaying_progress()
	await _test_unknown_ack_id_suspends_without_compaction()
	await _test_401_refreshes_once_and_403_suspends()
	await _test_persistent_401_is_an_authentication_diagnostic()
	await _test_invalid_durable_cursor_suspends_without_upload()
	await _test_snapshot_failure_retains_acknowledged_events()
	await _test_snapshot_must_cover_acknowledged_prefix()
	await _test_journal_replay_failure_never_reports_online()
	await _test_durable_cursor_reconciles_interrupted_compaction()
	await _test_pairing_delegates_without_blocking_local_state()

func _test_batches_205_events_in_order_and_compacts_after_snapshot() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(205, operations)
	var progress := FakeProgress.new(operations)
	var auth := FakeAuth.new()
	var transport := FakeTransportScript.new()
	for range_pair in [[1, 100], [101, 200], [201, 205]]:
		var ids: Array[String] = []
		for sequence in range(int(range_pair[0]), int(range_pair[1]) + 1):
			ids.append("event-%03d" % sequence)
		transport.enqueue(_response(200, {
			"accepted_event_ids": ids,
			"already_present_event_ids": [],
			"server_cursor": "cursor-%d" % range_pair[1],
			"request_id": "request-%d" % range_pair[1],
		}))
	var cursor := FakeCursorStore.new(operations)
	var service := CloudSyncScript.new(journal, progress, auth, transport, cursor, RetryPolicyScript.new(func(): return 0.0), CONFIG)
	var result: Dictionary = await service.sync_until_idle()
	assert_true(result.ok)
	assert_eq(transport.requests.size(), 3)
	assert_eq(transport.requests.map(func(request): return request.body.events.size()), [100, 100, 5])
	assert_eq(transport.requests[0].body.keys(), ["events"], "ingest body must contain only events")
	assert_eq(transport.requests[0].body.events[0].sequence, 1)
	assert_eq(transport.requests[1].body.events[0].sequence, 101)
	assert_eq(transport.requests[2].body.events[-1].sequence, 205)
	assert_eq(transport.requests[0].headers.get("Authorization"), "Bearer access-0")
	assert_eq(journal.compact_calls, [100, 200, 205])
	assert_eq(cursor.acknowledged_sequence, 205)
	assert_eq(journal.events, [])
	for sequence in [100, 200, 205]:
		var snapshot_index := operations.find("progress.snapshot", operations.find("cursor.save:%d" % (sequence - 100)) + 1 if sequence > 100 else 0)
		var compact_index := operations.find("journal.compact:%d" % sequence)
		var cursor_index := operations.find("cursor.save:%d" % sequence)
		assert_true(snapshot_index >= 0 and snapshot_index < compact_index, "snapshot must precede compaction")
		assert_true(cursor_index > snapshot_index and cursor_index < compact_index, "durable cursor must close the crash gap before compaction")

func _test_duplicate_ids_acknowledge_without_replaying_progress() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(2, operations)
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": [],
		"already_present_event_ids": ["event-001", "event-002"],
		"server_cursor": "cursor-2",
		"request_id": "duplicate-replay",
	}))
	var service: Variant = _service(journal, FakeProgress.new(operations), FakeAuth.new(), transport, FakeCursorStore.new(operations))
	assert_true((await service.sync_until_idle()).ok)
	assert_eq(journal.events, [])

func _test_unknown_ack_id_suspends_without_compaction() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": ["not-in-batch"],
		"already_present_event_ids": [],
		"server_cursor": "cursor-bad",
		"request_id": "invalid-ack",
	}))
	var service: Variant = _service(journal, FakeProgress.new(operations), FakeAuth.new(), transport, FakeCursorStore.new(operations))
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "invalid_acknowledgement")
	assert_eq(service.status().state, "suspended")
	assert_eq(journal.compact_calls, [])
	assert_eq(journal.events.size(), 1)

func _test_401_refreshes_once_and_403_suspends() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var auth := FakeAuth.new()
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(401, {"error": {"code": "AUTH_REQUIRED"}}))
	transport.enqueue(_response(403, {"error": {"code": "PAIRING_REQUIRED"}}))
	var service: Variant = _service(journal, FakeProgress.new(operations), auth, transport, FakeCursorStore.new(operations))
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(auth.refresh_calls, 1)
	assert_eq(transport.requests.size(), 2)
	assert_eq(result.get("error"), "permission")
	assert_eq(service.status().state, "suspended")
	assert_eq(journal.events.size(), 1)

func _test_snapshot_failure_retains_acknowledged_events() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var progress := FakeProgress.new(operations)
	progress.fail_snapshot = true
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": ["event-001"],
		"already_present_event_ids": [],
		"server_cursor": "cursor-1",
		"request_id": "snapshot-failure",
	}))
	var service: Variant = _service(journal, progress, FakeAuth.new(), transport, FakeCursorStore.new(operations))
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "snapshot_failed")
	assert_eq(journal.compact_calls, [])
	assert_eq(journal.events.size(), 1)

func _test_snapshot_must_cover_acknowledged_prefix() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var progress := FakeProgress.new(operations)
	progress.snapshot_last_sequence = 0
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": ["event-001"],
		"already_present_event_ids": [],
		"server_cursor": "1",
		"request_id": "snapshot-behind",
	}))
	var cursor := FakeCursorStore.new(operations)
	var service: Variant = _service(journal, progress, FakeAuth.new(), transport, cursor)
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "snapshot_behind")
	assert_eq(cursor.acknowledged_sequence, 0)
	assert_eq(journal.compact_calls, [])
	assert_eq(journal.events.size(), 1)

func _test_journal_replay_failure_never_reports_online() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	journal.replay_error = "journal_read_failed"
	var transport := FakeTransportScript.new()
	var service: Variant = _service(
		journal,
		FakeProgress.new(operations),
		FakeAuth.new(),
		transport,
		FakeCursorStore.new(operations),
	)
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "journal_replay_failed")
	assert_eq(service.status().state, "suspended")
	assert_eq(transport.requests, [])

func _test_durable_cursor_reconciles_interrupted_compaction() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(2, operations)
	var cursor := FakeCursorStore.new(operations)
	cursor.acknowledged_sequence = 2
	cursor.server_cursor = "2"
	var service: Variant = _service(
		journal,
		FakeProgress.new(operations),
		FakeAuth.new(),
		FakeTransportScript.new(),
		cursor,
	)
	journal.compact_error = ERR_CANT_CREATE
	var failed: Dictionary = await service.sync_until_idle()
	assert_eq(failed.get("error"), "journal_compaction_failed")
	assert_eq(service.status().pending_count, 0, "durably acknowledged events are not pending")
	assert_eq(journal.events.size(), 2)
	journal.compact_error = OK
	var recovered: Dictionary = await service.sync_until_idle()
	assert_true(recovered.ok)
	assert_eq(journal.events, [])
	assert_eq(journal.compact_calls, [2, 2])

func _test_persistent_401_is_an_authentication_diagnostic() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var auth := FakeAuth.new()
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(401, {"error": {"code": "AUTH_REQUIRED"}}))
	transport.enqueue(_response(401, {"error": {"code": "AUTH_REQUIRED"}}))
	var service: Variant = _service(journal, FakeProgress.new(operations), auth, transport, FakeCursorStore.new(operations))
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "authentication")
	assert_eq(auth.refresh_calls, 1)
	assert_eq(journal.events.size(), 1)

func _test_invalid_durable_cursor_suspends_without_upload() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var transport := FakeTransportScript.new()
	var cursor := FakeCursorStore.new(operations)
	cursor.cursor_diagnostic = "invalid_sync_cursor"
	var service: Variant = _service(journal, FakeProgress.new(operations), FakeAuth.new(), transport, cursor)
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "invalid_sync_cursor")
	assert_eq(transport.requests, [])

func _test_pairing_delegates_without_blocking_local_state() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(1, operations)
	var auth := FakeAuth.new()
	var service: Variant = _service(journal, FakeProgress.new(operations), auth, FakeTransportScript.new(), FakeCursorStore.new(operations))
	var result: Dictionary = await service.pair_device("123456", "profile-1", "모아")
	assert_true(result.ok)
	assert_eq(auth.pair_calls, [{"code": "123456", "profile_id": "profile-1", "display_name": "모아"}])
	assert_eq(journal.events.size(), 1, "pairing must never change local progress")

func _service(journal: Variant, progress: Variant, auth: Variant, transport: Variant, cursor: Variant) -> Variant:
	return CloudSyncScript.new(journal, progress, auth, transport, cursor, RetryPolicyScript.new(func(): return 0.0), CONFIG)

func _response(status: int, body: Dictionary) -> Dictionary:
	return {"ok": status >= 200 and status < 300, "status": status, "body": body.duplicate(true)}
