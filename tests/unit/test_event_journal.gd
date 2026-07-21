extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/events"
const EventJournal = preload("res://src/persistence/event_journal.gd")

func run(_tree: SceneTree) -> void:
	_cleanup()
	var journal := EventJournal.new()
	assert_true(journal.configure("profile-a", "device-a", "%s/events.jsonl" % BASE_PATH).ok)
	var first := journal.append(_answer_payload("session-a", 7))
	var second := journal.append(_answer_payload("session-a", 8))
	assert_true(first.ok and second.ok)
	assert_eq(first.event.sequence, 1)
	assert_eq(second.event.sequence, 2)
	var reopened := EventJournal.new()
	assert_true(reopened.configure("profile-a", "device-a", "%s/events.jsonl" % BASE_PATH).ok)
	assert_eq(reopened.replay().events.size(), 2)
	assert_eq(reopened.unacknowledged(0, 100).map(func(event): return event.sequence), [1, 2])
	var tail := FileAccess.open("%s/events.jsonl" % BASE_PATH, FileAccess.READ_WRITE)
	tail.seek_end()
	tail.store_string("{broken")
	tail.close()
	var recovered := EventJournal.new()
	var recovery := recovered.configure("profile-a", "device-a", "%s/events.jsonl" % BASE_PATH)
	assert_true(recovery.ok)
	assert_true(recovery.quarantined_tail)
	var replayed := recovered.replay()
	assert_eq(replayed.events.size(), 2)
	assert_true(FileAccess.file_exists("%s/events.jsonl.partial.corrupt" % BASE_PATH))
	var invalid_middle := FileAccess.open("%s/events.jsonl" % BASE_PATH, FileAccess.WRITE)
	invalid_middle.store_string(JSON.stringify(first.event) + "\n{broken}\n" + JSON.stringify(second.event) + "\n")
	invalid_middle.close()
	var middle := EventJournal.new()
	assert_eq(middle.configure("profile-a", "device-a", "%s/events.jsonl" % BASE_PATH).error, "invalid_record")
	_cleanup()

func _answer_payload(session_id: String, answer: int) -> Dictionary:
	return {"session_id": session_id, "client_timestamp": "2026-07-21T09:00:00Z", "event_type": "answer_submitted", "activity_id": "foundation_ten_rods", "content_version": "a-vertical-1", "question_seed": 42, "generator_id": "foundation_ten_rods", "band_id": "count_to_10", "resolved_parameters": {"left": 3, "right": 4}, "submitted_answer": answer, "correct_answer": 7, "correctness": answer == 7, "response_duration_ms": 1200, "hints": 0, "health_delta": 0, "combo": 1, "reward_delta": {"apples": 2}}

func _cleanup() -> void:
	for name in ["events.jsonl", "events.jsonl.partial.corrupt"]:
		var path := "%s/%s" % [BASE_PATH, name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
