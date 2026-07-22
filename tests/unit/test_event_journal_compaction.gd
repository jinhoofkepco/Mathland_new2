extends "res://tests/support/test_case.gd"

const EventJournalScript = preload("res://src/persistence/event_journal.gd")
const BASE_PATH := "user://tests/event_journal_compaction"

class CompactionCleanupFailJournal extends EventJournalScript:
	func _remove_path(path: String) -> Error:
		if path.ends_with(".compact.bak"):
			return ERR_CANT_CREATE
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

class ReplayFailJournal extends EventJournalScript:
	func replay() -> Dictionary:
		return {"ok": false, "error": "journal_read_failed"}

func run(_tree: SceneTree) -> void:
	_cleanup()
	var path := "%s/events.jsonl" % BASE_PATH
	var journal := EventJournalScript.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	assert_true(journal.append(_payload("coupon-1")).ok)
	assert_true(journal.append(_payload("coupon-2")).ok)
	assert_eq(journal.compact_through(1), OK)
	assert_eq(journal.replay().events.map(func(event): return event.sequence), [2])
	assert_eq(journal.append(_payload("coupon-3")).event.sequence, 3, "compaction mutated next sequence")
	var reopened := EventJournalScript.new()
	var reopened_result: Dictionary = reopened.configure("profile-a", "device-a", path)
	assert_true(reopened_result.ok, "reopen failed: %s" % reopened_result)
	if not reopened_result.ok:
		_cleanup()
		return
	assert_eq(reopened.replay().events.map(func(event): return event.sequence), [2, 3])
	assert_eq(reopened.append(_payload("coupon-4")).event.sequence, 4)
	assert_eq(reopened.compact_through(4), OK)
	assert_eq(reopened.replay().events, [])
	var empty_reopened := EventJournalScript.new()
	assert_true(empty_reopened.configure("profile-a", "device-a", path).ok)
	assert_eq(empty_reopened.append(_payload("coupon-5")).event.sequence, 5, "empty compacted journal lost durable sequence")
	_test_reopen_finishes_cursor_first_compaction()
	_test_unacknowledged_preserves_replay_failure()
	_test_unsafe_compaction_cursor_fails_closed()
	_test_cleanup_failure_keeps_the_live_journal_readable()
	_cleanup()

func _test_reopen_finishes_cursor_first_compaction() -> void:
	var path := "%s/interrupted.jsonl" % BASE_PATH
	var journal := EventJournalScript.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	assert_true(journal.append(_payload("interrupted-1")).ok)
	assert_true(journal.append(_payload("interrupted-2")).ok)
	assert_eq(journal.call("_save_compaction_cursor", 1), OK)
	var reopened := EventJournalScript.new()
	assert_true(reopened.configure("profile-a", "device-a", path).ok)
	assert_eq(reopened.replay().events.map(func(event): return event.sequence), [1, 2])
	assert_eq(reopened.compact_through(1), OK)
	assert_eq(reopened.replay().events.map(func(event): return event.sequence), [2])

func _test_unacknowledged_preserves_replay_failure() -> void:
	assert_eq(
		ReplayFailJournal.new().unacknowledged(0),
		{"ok": false, "error": "journal_read_failed"},
	)

func _test_unsafe_compaction_cursor_fails_closed() -> void:
	var path := "%s/unsafe.jsonl" % BASE_PATH
	var cursor_path := "%s.compaction.cursor.json" % path
	var file := FileAccess.open(cursor_path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"profile_id": "profile-a",
		"device_id": "device-a",
		"acknowledged_sequence": 9007199254740992.0,
	}))
	file.close()
	assert_eq(
		EventJournalScript.new().configure("profile-a", "device-a", path).get("error"),
		"compaction_cursor_failed",
	)

func _test_cleanup_failure_keeps_the_live_journal_readable() -> void:
	var path := "%s/cleanup.jsonl" % BASE_PATH
	var journal := CompactionCleanupFailJournal.new()
	assert_true(journal.configure("profile-a", "device-a", path).ok)
	assert_true(journal.append(_payload("cleanup-1")).ok)
	assert_true(journal.append(_payload("cleanup-2")).ok)
	assert_ne(journal.compact_through(1), OK)
	var replayed: Dictionary = journal.replay()
	assert_true(replayed.ok, "cleanup failure made the promoted journal unreadable")
	if replayed.get("ok", false):
		assert_eq(replayed.events.map(func(event): return event.sequence), [2])
	assert_eq(journal.append(_payload("cleanup-3")).event.sequence, 3)

func _payload(coupon_id: String) -> Dictionary:
	return {
		"client_timestamp": "2026-07-22T00:00:00Z",
		"event_type": "coupon_earned",
		"coupon_id": coupon_id,
	}

func _cleanup() -> void:
	for name in ["events.jsonl", "cleanup.jsonl", "interrupted.jsonl", "unsafe.jsonl"]:
		for suffix in ["", ".compaction.cursor.json", ".compaction.cursor.json.tmp", ".compaction.cursor.json.bak", ".compact.tmp", ".compact.bak"]:
			var path := "%s/%s%s" % [BASE_PATH, name, suffix]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
