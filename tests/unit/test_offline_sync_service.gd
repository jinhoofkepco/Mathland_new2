extends "res://tests/support/test_case.gd"

const SERVICE_PATH := "res://src/sync/sync_service.gd"
const OFFLINE_PATH := "res://src/sync/offline_sync_service.gd"
const RecordingJournalScript = preload("res://tests/support/recording_journal.gd")
const InMemoryProgressServiceScript = preload("res://tests/support/in_memory_progress_service.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const ContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const QuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")

class LocalRecordingJournal extends RefCounted:
	var events: Array[Dictionary] = []
	var replay_calls := 0

	func replay() -> Dictionary:
		replay_calls += 1
		return {"ok": true, "events": events.duplicate(true), "quarantined_tail": false}

func run(_tree: SceneTree) -> void:
	assert_true(ResourceLoader.exists(SERVICE_PATH), "missing SyncService class")
	assert_true(ResourceLoader.exists(OFFLINE_PATH), "missing OfflineSyncService class")
	if not ResourceLoader.exists(SERVICE_PATH) or not ResourceLoader.exists(OFFLINE_PATH):
		return
	var SyncScript: Variant = load(SERVICE_PATH)
	var OfflineScript: Variant = load(OFFLINE_PATH)
	var journal := LocalRecordingJournal.new()
	journal.events.assign([{"event_id": "one"}, {"event_id": "two"}, {"event_id": "three"}])
	var service: Variant = OfflineScript.new(journal)
	assert_eq(service.get_script().get_base_script(), SyncScript, "offline sync must implement the SyncService port")
	assert_eq(service.status(), {"state": "offline", "pending_count": 3, "last_success_at": null})
	var before := journal.events.duplicate(true)
	var diagnostics: Array[String] = []
	var statuses: Array[Dictionary] = []
	service.diagnostic.connect(func(code: String): diagnostics.append(code))
	service.status_changed.connect(func(status: Dictionary): statuses.append(status.duplicate(true)))
	assert_eq(service.request_sync(), {"ok": false, "error": "offline"})
	assert_eq(journal.events, before, "offline sync must never mutate or acknowledge events")
	assert_eq(diagnostics, ["offline"])
	assert_eq(statuses, [{"state": "offline", "pending_count": 3, "last_success_at": null}])
	assert_true(journal.replay_calls >= 2)
	var source := FileAccess.get_file_as_string(OFFLINE_PATH).to_lower()
	for forbidden in ["httprequest", "httpclient", "supabase", "http://", "https://"]:
		assert_false(forbidden in source, "offline sync contains network dependency: %s" % forbidden)
	var run_operations: Array[String] = []
	var run_journal := RecordingJournalScript.new("profile-a", "device-a", run_operations)
	var progress := InMemoryProgressServiceScript.new("profile-a", run_operations)
	var run_sync: Variant = OfflineScript.new(run_journal)
	assert_eq(run_sync.request_sync(), {"ok": false, "error": "offline"})
	var activity := ContentRepositoryScript.new().get_activity(&"foundation_ten_rods")
	var question := QuestionEngineScript.new().generate_question(activity, &"count_to_10", 42)
	var session := RunSessionScript.new(
		null,
		run_journal,
		progress,
		func(): return "2026-07-22T00:00:00Z",
		func(): return "offline-session"
	)
	assert_true(session.start_run(activity, question).ok, "offline sync failure blocked a local run")
