extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/events"
const EventJournal = preload("res://src/persistence/event_journal.gd")

class FaultInjectingJournal extends EventJournal:
	var failure_point := ""
	var promotion_failed := false

	func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
		if failure_point == "corrupt_write" and path.ends_with(".partial.corrupt.tmp"):
			return ERR_CANT_CREATE
		if failure_point == "before_rotation" and path.ends_with(".recovery.tmp"):
			return ERR_CANT_CREATE
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(bytes)
		file.flush()
		var error := file.get_error()
		file.close()
		return error

	func _rename_path(from_path: String, to_path: String) -> Error:
		if from_path.ends_with(".jsonl") and to_path.ends_with(".recovery.bak") and failure_point == "original_rotation":
			return ERR_CANT_CREATE
		if from_path.ends_with(".partial.corrupt.tmp") and to_path.ends_with(".partial.corrupt") and failure_point in ["corrupt_promotion", "corrupt_restoration"]:
			return ERR_CANT_CREATE
		if from_path.ends_with(".partial.corrupt.bak") and to_path.ends_with(".partial.corrupt") and failure_point == "corrupt_restoration":
			return ERR_CANT_CREATE
		if from_path.ends_with(".recovery.tmp") and to_path.ends_with(".jsonl") and failure_point in ["promotion", "restoration"] and not promotion_failed:
			promotion_failed = true
			return ERR_CANT_CREATE
		if from_path.ends_with(".recovery.bak") and to_path.ends_with(".jsonl") and failure_point == "restoration":
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))

	func _remove_path(path: String) -> Error:
		if path.ends_with(".recovery.bak") and failure_point == "journal_backup_cleanup":
			return ERR_CANT_CREATE
		if path.ends_with(".partial.corrupt.bak") and failure_point == "corrupt_backup_cleanup":
			return ERR_CANT_CREATE
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	func _open_append_file(path: String, mode: int) -> FileAccess:
		if failure_point == "append_open":
			return null
		return FileAccess.open(path, mode)

	func _write_append_file(file: FileAccess, bytes: PackedByteArray) -> Error:
		if failure_point == "append_write":
			return ERR_CANT_CREATE
		file.store_buffer(bytes)
		return file.get_error()

	func _flush_append_file(file: FileAccess) -> Error:
		if failure_point == "append_flush":
			return ERR_CANT_CREATE
		file.flush()
		return file.get_error()

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
	_test_semantically_invalid_unterminated_tail_is_not_quarantined()
	_cleanup()
	_test_wrong_sequence_unterminated_tail_is_not_quarantined()
	_cleanup()
	_test_unacknowledged_caps_at_one_hundred_without_mutation()
	_cleanup()
	_test_tail_quarantine_preserves_exact_bytes()
	_cleanup()
	_test_valid_unterminated_record_gets_separator_before_append()
	_cleanup()
	_test_corrupt_artifact_write_failure_preserves_original()
	_cleanup()
	_test_quarantine_failure_before_rotation_preserves_original()
	_cleanup()
	_test_quarantine_promotion_failure_restores_original()
	_cleanup()
	_test_interrupted_restoration_recovers_on_startup()
	_cleanup()
	_test_startup_prefers_valid_backup_over_wrong_scope_original()
	_cleanup()
	_test_startup_prefers_valid_backup_over_stale_recovery_temp()
	_cleanup()
	_test_startup_preserves_all_candidates_when_none_are_valid()
	_cleanup()
	_test_startup_promotes_lone_valid_recovery_temp()
	_cleanup()
	_test_startup_cleanup_failure_preserves_candidates()
	_cleanup()
	_test_original_rotation_failure_preserves_original()
	_cleanup()
	_test_corrupt_promotion_failure_restores_old_artifact()
	_cleanup()
	_test_corrupt_restoration_failure_retains_both_artifacts()
	_cleanup()
	_test_corrupt_backup_cleanup_failure_preserves_artifacts()
	_cleanup()
	_test_startup_recovers_interrupted_corrupt_artifact_promotion()
	_cleanup()
	_test_append_io_failures_do_not_advance_sequence()
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

func _test_semantically_invalid_unterminated_tail_is_not_quarantined() -> void:
	var prepared := _prepare_valid_journal("semantic-tail.jsonl", 1)
	var invalid_event: Dictionary = prepared.events[0].duplicate(true)
	invalid_event.erase("correctness")
	var original: PackedByteArray = prepared.bytes.duplicate()
	original.append_array(JSON.stringify(invalid_event).to_utf8_buffer())
	assert_eq(_write_bytes_direct(prepared.path, original), OK)
	var result := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "invalid_record")
	assert_true(_read_bytes(prepared.path) == original, "schema-invalid JSON tail changed journal bytes")
	assert_false(FileAccess.file_exists("%s.partial.corrupt" % prepared.path))

func _test_wrong_sequence_unterminated_tail_is_not_quarantined() -> void:
	var prepared := _prepare_valid_journal("sequence-tail.jsonl", 1)
	var invalid_event: Dictionary = prepared.events[0].duplicate(true)
	invalid_event.sequence = 99
	var original: PackedByteArray = prepared.bytes.duplicate()
	original.append_array(JSON.stringify(invalid_event).to_utf8_buffer())
	assert_eq(_write_bytes_direct(prepared.path, original), OK)
	var result := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_false(result.ok)
	assert_eq(result.get("error", ""), "invalid_sequence")
	assert_true(_read_bytes(prepared.path) == original, "wrong-sequence JSON tail changed journal bytes")
	assert_false(FileAccess.file_exists("%s.partial.corrupt" % prepared.path))

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

func _test_tail_quarantine_preserves_exact_bytes() -> void:
	var prepared := _prepare_corrupt_journal("exact.jsonl")
	var recovered := EventJournal.new()
	var recovery := recovered.configure("profile-a", "device-a", prepared.path)
	assert_true(recovery.ok)
	assert_true(recovery.quarantined_tail)
	assert_true(_read_bytes(prepared.path) == prepared.prefix, "valid prefix bytes changed")
	assert_true(_read_bytes("%s.partial.corrupt" % prepared.path) == prepared.tail, "corrupt tail bytes changed")
	assert_eq(recovered.replay().events.size(), 2)

func _test_valid_unterminated_record_gets_separator_before_append() -> void:
	var path := _path("valid-unterminated.jsonl")
	var writer := EventJournal.new()
	assert_true(writer.configure("profile-a", "device-a", path).ok)
	assert_true(writer.append(_answer_payload("session-a", 7)).ok)
	var unterminated := _read_bytes(path)
	unterminated.resize(unterminated.size() - 1)
	assert_eq(_write_bytes_direct(path, unterminated), OK)
	var reopened := EventJournal.new()
	assert_true(reopened.configure("profile-a", "device-a", path).ok)
	assert_true(reopened.append(_answer_payload("session-a", 8)).ok)
	var replayed := reopened.replay()
	assert_true(replayed.ok)
	assert_eq(replayed.get("events", []).size(), 2)

func _test_corrupt_artifact_write_failure_preserves_original() -> void:
	var prepared := _prepare_corrupt_journal("corrupt-write.jsonl")
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "corrupt_write"
	var failed := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original, "corrupt write failure changed original")

func _test_quarantine_failure_before_rotation_preserves_original() -> void:
	var prepared := _prepare_corrupt_journal("before-rotation.jsonl")
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "before_rotation"
	var failed := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original, "original changed before rotation")
	var recovered := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_true(recovered.ok)

func _test_quarantine_promotion_failure_restores_original() -> void:
	var prepared := _prepare_corrupt_journal("promotion.jsonl")
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "promotion"
	var failed := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original, "promotion failure did not restore original")
	var recovered := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_true(recovered.ok)

func _test_interrupted_restoration_recovers_on_startup() -> void:
	var prepared := _prepare_corrupt_journal("restoration.jsonl")
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "restoration"
	var failed := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(failed.ok)
	assert_eq(failed.get("error", ""), "tail_quarantine_failed")
	var backup_path := "%s.recovery.bak" % prepared.path
	assert_true(FileAccess.file_exists(backup_path))
	if FileAccess.file_exists(backup_path):
		assert_true(_read_bytes(backup_path) == prepared.original, "recovery backup lost original bytes")
		var recovered := EventJournal.new()
		var recovery := recovered.configure("profile-a", "device-a", prepared.path)
		assert_true(recovery.ok)
		assert_eq(recovered.replay().events.size(), 2)
		assert_true(_read_bytes(prepared.path) == prepared.prefix, "startup recovery changed prefix bytes")

func _test_startup_prefers_valid_backup_over_wrong_scope_original() -> void:
	var prepared := _prepare_valid_journal("candidate-original.jsonl", 2)
	var wrong_scope: Dictionary = prepared.events[0].duplicate(true)
	wrong_scope.profile_id = "profile-b"
	var wrong_bytes := (JSON.stringify(wrong_scope) + "\n").to_utf8_buffer()
	assert_eq(_write_bytes_direct(prepared.path, wrong_bytes), OK)
	assert_eq(_write_bytes_direct("%s.recovery.bak" % prepared.path, prepared.bytes), OK)
	var journal := EventJournal.new()
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_true(recovery.ok)
	assert_true(_read_bytes(prepared.path) == prepared.bytes, "valid backup was not selected")
	assert_eq(journal.replay().get("events", []).size(), 2)

func _test_startup_prefers_valid_backup_over_stale_recovery_temp() -> void:
	var prepared := _prepare_valid_journal("candidate-temp.jsonl", 2)
	var stale_event: Dictionary = prepared.events[0].duplicate(true)
	stale_event.sequence = 7
	var stale_bytes := (JSON.stringify(stale_event) + "\n").to_utf8_buffer()
	assert_eq(_write_bytes_direct("%s.recovery.bak" % prepared.path, prepared.bytes), OK)
	assert_eq(_write_bytes_direct("%s.recovery.tmp" % prepared.path, stale_bytes), OK)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(prepared.path)), OK)
	var journal := EventJournal.new()
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_true(recovery.ok)
	assert_true(_read_bytes(prepared.path) == prepared.bytes, "stale recovery temp replaced valid backup")
	assert_eq(journal.replay().get("events", []).size(), 2)

func _test_startup_preserves_all_candidates_when_none_are_valid() -> void:
	var prepared := _prepare_valid_journal("candidate-invalid.jsonl", 1)
	var wrong_scope: Dictionary = prepared.events[0].duplicate(true)
	wrong_scope.profile_id = "profile-b"
	var backup_bytes := (JSON.stringify(wrong_scope) + "\n").to_utf8_buffer()
	var temp_bytes := JSON.stringify({"not": "a learning event"}).to_utf8_buffer()
	assert_eq(_write_bytes_direct("%s.recovery.bak" % prepared.path, backup_bytes), OK)
	assert_eq(_write_bytes_direct("%s.recovery.tmp" % prepared.path, temp_bytes), OK)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(prepared.path)), OK)
	var recovery := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_eq(recovery.get("error", ""), "tail_recovery_failed")
	assert_true(_read_bytes("%s.recovery.bak" % prepared.path) == backup_bytes)
	assert_true(_read_bytes("%s.recovery.tmp" % prepared.path) == temp_bytes)
	assert_false(FileAccess.file_exists(prepared.path))

func _test_startup_promotes_lone_valid_recovery_temp() -> void:
	var prepared := _prepare_valid_journal("candidate-lone-temp.jsonl", 2)
	assert_eq(_write_bytes_direct("%s.recovery.tmp" % prepared.path, prepared.bytes), OK)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(prepared.path)), OK)
	var journal := EventJournal.new()
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_true(recovery.ok)
	assert_true(_read_bytes(prepared.path) == prepared.bytes)
	assert_eq(journal.replay().get("events", []).size(), 2)

func _test_startup_cleanup_failure_preserves_candidates() -> void:
	var prepared := _prepare_valid_journal("candidate-cleanup.jsonl", 2)
	assert_eq(_write_bytes_direct("%s.recovery.bak" % prepared.path, prepared.bytes), OK)
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "journal_backup_cleanup"
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_eq(recovery.get("error", ""), "tail_recovery_failed")
	assert_true(_read_bytes(prepared.path) == prepared.bytes)
	assert_true(_read_bytes("%s.recovery.bak" % prepared.path) == prepared.bytes)

func _test_original_rotation_failure_preserves_original() -> void:
	var prepared := _prepare_corrupt_journal("rotation-failure.jsonl")
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "original_rotation"
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_eq(recovery.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original)
	assert_false(FileAccess.file_exists("%s.recovery.bak" % prepared.path))

func _test_corrupt_promotion_failure_restores_old_artifact() -> void:
	var prepared := _prepare_corrupt_journal("corrupt-promotion.jsonl")
	var corrupt_path := "%s.partial.corrupt" % prepared.path
	var old_artifact := "old-corrupt-artifact".to_utf8_buffer()
	assert_eq(_write_bytes_direct(corrupt_path, old_artifact), OK)
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "corrupt_promotion"
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_eq(recovery.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original)
	assert_true(_read_bytes(corrupt_path) == old_artifact, "old corrupt artifact was lost")
	assert_true(_read_bytes("%s.partial.corrupt.tmp" % prepared.path) == prepared.tail, "new corrupt bytes were lost")

func _test_corrupt_restoration_failure_retains_both_artifacts() -> void:
	var prepared := _prepare_corrupt_journal("corrupt-restoration.jsonl")
	var corrupt_path := "%s.partial.corrupt" % prepared.path
	var old_artifact := "old-corrupt-artifact".to_utf8_buffer()
	assert_eq(_write_bytes_direct(corrupt_path, old_artifact), OK)
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "corrupt_restoration"
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_true(_read_bytes(prepared.path) == prepared.original)
	assert_true(_read_bytes("%s.partial.corrupt.bak" % prepared.path) == old_artifact)
	assert_true(_read_bytes("%s.partial.corrupt.tmp" % prepared.path) == prepared.tail)

func _test_corrupt_backup_cleanup_failure_preserves_artifacts() -> void:
	var prepared := _prepare_corrupt_journal("corrupt-cleanup.jsonl")
	var corrupt_path := "%s.partial.corrupt" % prepared.path
	var old_artifact := "old-corrupt-artifact".to_utf8_buffer()
	assert_eq(_write_bytes_direct(corrupt_path, old_artifact), OK)
	var journal := FaultInjectingJournal.new()
	journal.failure_point = "corrupt_backup_cleanup"
	var recovery := journal.configure("profile-a", "device-a", prepared.path)
	assert_false(recovery.ok)
	assert_eq(recovery.get("error", ""), "tail_quarantine_failed")
	assert_true(_read_bytes(prepared.path) == prepared.original)
	assert_true(_read_bytes(corrupt_path) == prepared.tail)
	assert_true(_read_bytes("%s.partial.corrupt.bak" % prepared.path) == old_artifact)

func _test_startup_recovers_interrupted_corrupt_artifact_promotion() -> void:
	var prepared := _prepare_valid_journal("corrupt-startup.jsonl", 1)
	var old_artifact := "old-corrupt-artifact".to_utf8_buffer()
	var new_artifact := "new-corrupt-artifact".to_utf8_buffer()
	assert_eq(_write_bytes_direct("%s.partial.corrupt.bak" % prepared.path, old_artifact), OK)
	assert_eq(_write_bytes_direct("%s.partial.corrupt.tmp" % prepared.path, new_artifact), OK)
	var recovery := EventJournal.new().configure("profile-a", "device-a", prepared.path)
	assert_true(recovery.ok)
	assert_true(_read_bytes("%s.partial.corrupt" % prepared.path) == new_artifact)
	assert_false(FileAccess.file_exists("%s.partial.corrupt.bak" % prepared.path))
	assert_false(FileAccess.file_exists("%s.partial.corrupt.tmp" % prepared.path))

func _test_append_io_failures_do_not_advance_sequence() -> void:
	for failure_point in ["append_open", "append_write", "append_flush"]:
		var path := _path("%s.jsonl" % failure_point)
		var journal := FaultInjectingJournal.new()
		assert_true(journal.configure("profile-a", "device-a", path).ok)
		journal.failure_point = failure_point
		var failed := journal.append(_answer_payload("session-a", 7))
		assert_false(failed.ok, "%s unexpectedly appended" % failure_point)
		assert_eq(failed.get("error", ""), "journal_open_failed" if failure_point == "append_open" else "journal_write_failed")
		journal.failure_point = ""
		var retry := journal.append(_answer_payload("session-a", 7))
		assert_true(retry.ok)
		assert_eq(retry.event.sequence, 1, "%s advanced sequence" % failure_point)

func _prepare_valid_journal(name: String, count: int) -> Dictionary:
	var path := _path(name)
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	var events: Array[Dictionary] = []
	for index in count:
		var appended := journal.append(_answer_payload("session-a", 7 + index))
		assert_true(appended.ok)
		events.append(appended.event)
	return {"path": path, "bytes": _read_bytes(path), "events": events}

func _prepare_corrupt_journal(name: String) -> Dictionary:
	var path := _path(name)
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	var first := journal.append(_answer_payload("session-a", 7))
	var second := journal.append(_answer_payload("session-a", 8))
	assert_true(first.ok and second.ok)
	var prefix := ("  %s  \n\t%s \n" % [JSON.stringify(first.event), JSON.stringify(second.event)]).to_utf8_buffer()
	var tail := PackedByteArray([0x7b, 0xff, 0x00, 0x41])
	var original := prefix.duplicate()
	original.append_array(tail)
	assert_eq(_write_bytes_direct(path, original), OK)
	return {"path": path, "prefix": prefix, "tail": tail, "original": original}

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

func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

func _write_bytes_direct(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func _cleanup() -> void:
	for journal_name in ["events.jsonl", "first.jsonl", "second.jsonl", "scope.jsonl", "invalid.jsonl", "semantic-tail.jsonl", "sequence-tail.jsonl", "limits.jsonl", "exact.jsonl", "valid-unterminated.jsonl", "corrupt-write.jsonl", "before-rotation.jsonl", "promotion.jsonl", "restoration.jsonl", "candidate-original.jsonl", "candidate-temp.jsonl", "candidate-invalid.jsonl", "candidate-lone-temp.jsonl", "candidate-cleanup.jsonl", "rotation-failure.jsonl", "corrupt-promotion.jsonl", "corrupt-restoration.jsonl", "corrupt-cleanup.jsonl", "corrupt-startup.jsonl", "append_open.jsonl", "append_write.jsonl", "append_flush.jsonl"]:
		for suffix in ["", ".partial.corrupt", ".partial.corrupt.tmp", ".partial.corrupt.bak", ".recovery.tmp", ".recovery.bak"]:
			var path := _path("%s%s" % [journal_name, suffix])
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
