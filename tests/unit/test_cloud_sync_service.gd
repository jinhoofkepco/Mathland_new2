extends "res://tests/support/test_case.gd"

const CloudSyncScript = preload("res://src/sync/cloud_sync_service.gd")
const RetryPolicyScript = preload("res://src/sync/sync_retry_policy.gd")
const FakeTransportScript = preload("res://tests/support/fake_http_json_transport.gd")
const AdaptiveBandSelectorScript = preload("res://src/content/adaptive_band_selector.gd")

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
	var session_result := {"ok": true}
	var refresh_result := {"ok": true}
	var re_pair_result := {"ok": true, "family_id": "family-1"}
	var re_pair_calls: Array[Dictionary] = []

	func ensure_session(force_refresh: bool = false) -> Dictionary:
		if force_refresh:
			refresh_calls += 1
			return refresh_result.duplicate(true)
		return session_result.duplicate(true)

	func authorization_header() -> String:
		return "Bearer access-%d" % refresh_calls

	func pair(code: String, profile_id: String, display_name: String) -> Dictionary:
		pair_calls.append({"code": code, "profile_id": profile_id, "display_name": display_name})
		return {"ok": true, "family_id": "family-1", "profile_id": profile_id, "device_id": "device-1"}

	func re_pair(code: String, profile_id: String, display_name: String) -> Dictionary:
		re_pair_calls.append({"code": code, "profile_id": profile_id, "display_name": display_name})
		return re_pair_result.duplicate(true)

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
	await _test_batches_205_events_in_order_and_retains_durable_history()
	await _test_duplicate_ids_acknowledge_without_replaying_progress()
	await _test_unknown_ack_id_suspends_without_compaction()
	await _test_401_refreshes_once_and_403_suspends()
	await _test_persistent_401_is_an_authentication_diagnostic()
	await _test_invalid_durable_cursor_suspends_without_upload()
	await _test_snapshot_failure_retains_acknowledged_events()
	await _test_snapshot_must_cover_acknowledged_prefix()
	await _test_journal_replay_failure_never_reports_online()
	await _test_durable_cursor_hydrates_before_sync_and_prevents_resend()
	await _test_acknowledged_answers_remain_available_to_adaptive_selection()
	await _test_re_pair_required_is_not_collapsed_to_authentication()
	await _test_forced_refresh_re_pair_required_is_preserved()
	await _test_explicit_re_pair_is_a_separate_action()
	await _test_pairing_delegates_without_blocking_local_state()

func _test_batches_205_events_in_order_and_retains_durable_history() -> void:
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
	assert_eq(journal.compact_calls, [], "ACK must not delete replay history in this release")
	assert_eq(cursor.acknowledged_sequence, 205)
	assert_eq(journal.events.size(), 205, "ACKed history is required for run recovery and adaptation")
	assert_eq(operations, [
		"progress.snapshot", "cursor.save:100",
		"progress.snapshot", "cursor.save:200",
		"progress.snapshot", "cursor.save:205",
	], "snapshot must precede each durable cursor advance")

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
	assert_eq(journal.events.size(), 2)

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
	assert_eq(service.status().state, "suspended", "journal corruption was hidden behind connecting state")
	assert_eq(service.status().diagnostic, "journal_replay_failed")
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "journal_replay_failed")
	assert_eq(service.status().state, "suspended")
	assert_eq(transport.requests, [])

func _test_durable_cursor_hydrates_before_sync_and_prevents_resend() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(3, operations)
	var cursor := FakeCursorStore.new(operations)
	cursor.acknowledged_sequence = 2
	cursor.server_cursor = "2"
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": ["event-003"],
		"already_present_event_ids": [],
		"server_cursor": "3",
		"request_id": "cursor-resume",
	}))
	var service: Variant = _service(
		journal,
		FakeProgress.new(operations),
		FakeAuth.new(),
		transport,
		cursor,
	)
	assert_eq(service.status().state, "connecting", "a new cloud service must not claim optimistic online state")
	assert_eq(service.status().pending_count, 1, "durable cursor must hydrate before the first drain")
	var recovered: Dictionary = await service.sync_until_idle()
	assert_true(recovered.ok)
	assert_eq(transport.requests.size(), 1)
	assert_eq(transport.requests[0].body.events.map(func(event): return event.sequence), [3])
	assert_eq(journal.events.size(), 3)
	assert_eq(journal.compact_calls, [])
	assert_eq(service.status().pending_count, 0)

func _test_acknowledged_answers_remain_available_to_adaptive_selection() -> void:
	var operations: Array[String] = []
	var journal := FakeJournal.new(3, operations)
	for index in journal.events.size():
		journal.events[index].merge({
			"event_type": "answer_submitted",
			"activity_id": "foundations_counting",
			"content_version": "1.0.0",
			"question_seed": index + 10,
			"correctness": true,
			"hints": 0,
		}, true)
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(200, {
		"accepted_event_ids": ["event-001", "event-002", "event-003"],
		"already_present_event_ids": [],
		"server_cursor": "adaptive-3",
		"request_id": "adaptive-retention",
	}))
	var service: Variant = _service(
		journal, FakeProgress.new(operations), FakeAuth.new(), transport, FakeCursorStore.new(operations)
	)
	assert_true((await service.sync_until_idle()).ok)
	var activity := {
		"activity_id": "foundations_counting",
		"content_version": "1.0.0",
		"difficulty_bands": [
			{"band_id": "intro"}, {"band_id": "practice"}, {"band_id": "challenge"},
		],
		"adaptive_policy": {
			"min_band_id": "intro",
			"max_band_id": "challenge",
			"window_size": 3,
			"promote_correctness": 0.8,
			"demote_correctness": 0.3,
		},
	}
	assert_eq(
		AdaptiveBandSelectorScript.new().select(activity, &"practice", journal.replay().events, true),
		&"challenge",
		"sync ACK discarded the evidence used by adaptive difficulty",
	)

func _test_re_pair_required_is_not_collapsed_to_authentication() -> void:
	var operations: Array[String] = []
	var auth := FakeAuth.new()
	auth.session_result = {"ok": false, "error": "re_pair_required", "status": 401}
	var service: Variant = _service(
		FakeJournal.new(1, operations),
		FakeProgress.new(operations),
		auth,
		FakeTransportScript.new(),
		FakeCursorStore.new(operations),
	)
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "re_pair_required")
	assert_eq(service.status().diagnostic, "re_pair_required")

func _test_forced_refresh_re_pair_required_is_preserved() -> void:
	var operations: Array[String] = []
	var auth := FakeAuth.new()
	auth.refresh_result = {"ok": false, "error": "re_pair_required", "status": 401}
	var transport := FakeTransportScript.new()
	transport.enqueue(_response(401, {"error": {"code": "AUTH_REQUIRED"}}))
	var service: Variant = _service(
		FakeJournal.new(1, operations),
		FakeProgress.new(operations),
		auth,
		transport,
		FakeCursorStore.new(operations),
	)
	var result: Dictionary = await service.sync_until_idle()
	assert_eq(result.get("error"), "re_pair_required")
	assert_eq(service.status().diagnostic, "re_pair_required")

func _test_explicit_re_pair_is_a_separate_action() -> void:
	var operations: Array[String] = []
	var auth := FakeAuth.new()
	auth.session_result = {"ok": false, "error": "re_pair_required", "status": 401}
	var service: Variant = _service(
		FakeJournal.new(1, operations),
		FakeProgress.new(operations),
		auth,
		FakeTransportScript.new(),
		FakeCursorStore.new(operations),
	)
	assert_eq((await service.sync_until_idle()).get("error"), "re_pair_required")
	assert_true(service.has_method("re_pair_device"), "cloud sync has no explicit re-pair boundary")
	if not service.has_method("re_pair_device"):
		return
	var result: Dictionary = await service.re_pair_device("123456", "profile-1", "모아")
	assert_true(result.ok)
	assert_eq(auth.re_pair_calls, [{"code": "123456", "profile_id": "profile-1", "display_name": "모아"}])
	assert_eq(service.status().diagnostic, "")

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
	assert_eq(service.status().state, "suspended")
	assert_eq(service.status().diagnostic, "invalid_sync_cursor")
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
