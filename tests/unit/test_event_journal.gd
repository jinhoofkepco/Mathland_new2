extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/events"
const EventJournal = preload("res://src/persistence/event_journal.gd")

func run(_tree: SceneTree) -> void:
	_cleanup()
	_test_append_reopen_and_tail_recovery()
	_cleanup()
	_test_reserved_context_and_reconfigure_sequence()
	_cleanup()
	_test_scope_mismatch_is_rejected()
	_cleanup()
	_test_complete_blank_and_invalid_records_are_errors()
	_cleanup()
	_test_unacknowledged_caps_at_one_hundred_without_mutation()
	_cleanup()

func _test_append_reopen_and_tail_recovery() -> void:
	var path := _path("events.jsonl")
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	var first := journal.append(_answer_payload("session-a", 7))
	var second := journal.append(_answer_payload("session-a", 8))
	assert_true(first.ok and second.ok)
	assert_eq(first.event.sequence, 1)
	assert_eq(second.event.sequence, 2)
	var reopened := EventJournal.new()
	assert_true(reopened.configure("profile-a", "device-a", path).ok)
	assert_eq(reopened.replay().events.size(), 2)
	assert_eq(reopened.unacknowledged(0, 100).map(func(event): return event.sequence), [1, 2])
	var tail := FileAccess.open(path, FileAccess.READ_WRITE)
	tail.seek_end()
	tail.store_string("{broken")
	tail.close()
	var recovered := EventJournal.new()
	var recovery := recovered.configure("profile-a", "device-a", path)
	assert_true(recovery.ok)
	assert_true(recovery.quarantined_tail)
	assert_eq(recovered.replay().events.size(), 2)
	assert_true(FileAccess.file_exists("%s.partial.corrupt" % path))

func _test_reserved_context_and_reconfigure_sequence() -> void:
	var first_path := _path("first.jsonl")
	var second_path := _path("second.jsonl")
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", first_path).ok)
	var payload := _answer_payload("session-a", 7)
	payload["profile_id"] = "profile-b"
	payload["device_id"] = "device-b"
	payload["sequence"] = 99
	var first := journal.append(payload)
	assert_true(first.ok)
	assert_eq(first.event.profile_id, "profile-a")
	assert_eq(first.event.device_id, "device-a")
	assert_eq(first.event.sequence, 1)
	assert_eq(journal.append(_answer_payload("session-a", 8)).event.sequence, 2)
	assert_true(journal.configure("profile-a", "device-a", second_path).ok)
	assert_eq(journal.append(_answer_payload("session-b", 7)).event.sequence, 1)
	assert_true(journal.configure("profile-a", "device-a", first_path).ok)
	assert_eq(journal.append(_answer_payload("session-a", 7)).event.sequence, 3)

func _test_scope_mismatch_is_rejected() -> void:
	var path := _path("scope.jsonl")
	var writer := EventJournal.new()
	assert_true(writer.configure("profile-a", "device-a", path).ok)
	assert_true(writer.append(_answer_payload("session-a", 7)).ok)
	var wrong_profile := EventJournal.new().configure("profile-b", "device-a", path)
	assert_false(wrong_profile.ok)
	assert_eq(wrong_profile.get("error", ""), "scope_mismatch")
	var wrong_device := EventJournal.new().configure("profile-a", "device-b", path)
	assert_false(wrong_device.ok)
	assert_eq(wrong_device.get("error", ""), "scope_mismatch")

func _test_complete_blank_and_invalid_records_are_errors() -> void:
	var path := _path("invalid.jsonl")
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	var event: Dictionary = journal.append(_answer_payload("session-a", 7)).event
	_write_text(path, JSON.stringify(event) + "\n\n")
	var blank := EventJournal.new().configure("profile-a", "device-a", path)
	assert_false(blank.ok)
	assert_eq(blank.get("error", ""), "invalid_record")
	assert_eq(blank.get("line", 0), 2)
	_write_text(path, JSON.stringify(event) + "\n{broken}\n")
	var complete_invalid := EventJournal.new().configure("profile-a", "device-a", path)
	assert_false(complete_invalid.ok)
	assert_eq(complete_invalid.get("error", ""), "invalid_record")
	assert_eq(complete_invalid.get("line", 0), 2)

func _test_unacknowledged_caps_at_one_hundred_without_mutation() -> void:
	var path := _path("limits.jsonl")
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	for index in 101:
		assert_true(journal.append(_answer_payload("session-limit", index)).ok)
	var before := _read_text(path)
	var first_batch := journal.unacknowledged(0, 101)
	assert_eq(first_batch.size(), 100)
	assert_eq(first_batch[0].sequence, 1)
	assert_eq(first_batch[99].sequence, 100)
	assert_eq(journal.unacknowledged(99, 100).map(func(event): return event.sequence), [100, 101])
	assert_eq(journal.unacknowledged(0, 0), [])
	assert_eq(_read_text(path), before)

func _answer_payload(session_id: String, answer: Variant) -> Dictionary:
	return {"session_id": session_id, "client_timestamp": "2026-07-21T09:00:00Z", "event_type": "answer_submitted", "activity_id": "foundation_ten_rods", "content_version": "a-vertical-1", "question_seed": 42, "generator_id": "foundation_ten_rods", "band_id": "count_to_10", "resolved_parameters": {"left": 3, "right": 4}, "submitted_answer": answer, "correct_answer": 7, "correctness": answer == 7, "response_duration_ms": 1200, "hints": 0, "health_delta": 0, "combo": 1, "reward_delta": {"apples": 2}}

func _coupon_payload(coupon_id: String) -> Dictionary:
	return {"client_timestamp": "2026-07-21T09:00:00Z", "event_type": "coupon_earned", "coupon_id": coupon_id}

func _path(name: String) -> String:
	return "%s/%s" % [BASE_PATH, name]

func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var content := file.get_as_text()
	file.close()
	return content

func _cleanup() -> void:
	for name in ["events.jsonl", "events.jsonl.partial.corrupt", "first.jsonl", "second.jsonl", "scope.jsonl", "invalid.jsonl", "limits.jsonl"]:
		var path := _path(name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
