extends "res://tests/support/test_case.gd"

const BASE_PATH := "user://tests/lifecycle_resume/profiles"
const PROFILE_ID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
const DEVICE_ID := "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
const SESSION_ID := "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
const LIFECYCLE_PATH := "res://src/app/app_lifecycle.gd"
const CHECKPOINT_PATH := "res://src/persistence/run_checkpoint_store.gd"
const SHELL_BASE_PATH := "user://tests/lifecycle_shell"
const AppRouteScript = preload("res://src/app/app_route.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const EventJournalScript = preload("res://src/persistence/event_journal.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const VerticalSliceContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const VerticalSliceQuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")
const AppShellScene = preload("res://scenes/app/app_shell.tscn")

class FlushCountingJournal extends EventJournalScript:
	var flush_calls := 0

	func flush() -> Error:
		flush_calls += 1
		return OK

class CompletionFailingJournal extends FlushCountingJournal:
	var fail_completion := false

	func append(payload: Dictionary) -> Dictionary:
		if fail_completion and payload.get("event_type") == "run_completed":
			return {"ok": false, "error": "simulated_completion_failure"}
		return super.append(payload)

class ReplayOverrideJournal extends RefCounted:
	var events: Array

	func _init(values: Array) -> void:
		events = values.duplicate(true)

	func replay() -> Dictionary:
		return {"ok": true, "events": events.duplicate(true), "quarantined_tail": false}

	func flush() -> Error:
		return OK

	func append(_payload: Dictionary) -> Dictionary:
		return {"ok": false, "error": "read_only_test_journal"}

class FailOnceCompletionProgress extends RefCounted:
	var inner: Node
	var fail_completion := true

	func _init(service: Node) -> void:
		inner = service

	func snapshot() -> Dictionary:
		return inner.snapshot()

	func commit(event: Dictionary) -> Error:
		if fail_completion and event.get("event_type") == "run_completed":
			fail_completion = false
			return FAILED
		return inner.commit(event)

class ActivityBackRouter extends RefCounted:
	var back_calls := 0

	func current_route() -> StringName:
		return AppRouteScript.ACTIVITY_RUN

	func back() -> bool:
		back_calls += 1
		return true

class CheckpointFailingLifecycle extends RefCounted:
	var flush_calls := 0

	func flush_and_checkpoint() -> Dictionary:
		flush_calls += 1
		return {"ok": false, "error": "simulated_disk_full"}

class TestStoreFactory extends RefCounted:
	func create_store(profile_id: String) -> Variant:
		return AtomicJsonStoreScript.new("%s/%s" % [BASE_PATH, profile_id])

class FakeRouter extends RefCounted:
	var calls: Array[Dictionary] = []

	func reset(route: StringName, params: Dictionary = {}) -> Dictionary:
		calls.append({"route": route, "params": params.duplicate(false)})
		return {"ok": true}

class TestAudioService extends Node:
	func apply_settings(_settings: Dictionary) -> bool:
		return true

	func play_sfx(_sfx_id: StringName) -> bool:
		return false

	func play_voice(_dialogue_id: StringName) -> bool:
		return false

	func stop_voice() -> void:
		pass

func run(tree: SceneTree) -> void:
	_cleanup()
	assert_true(EventJournalScript.new().has_method("flush"), "EventJournal must expose a lifecycle durability flush")
	assert_true(ResourceLoader.exists(CHECKPOINT_PATH), "missing RunCheckpointStore class")
	assert_true(ResourceLoader.exists(LIFECYCLE_PATH), "missing AppLifecycle class")
	if not ResourceLoader.exists(CHECKPOINT_PATH) or not ResourceLoader.exists(LIFECYCLE_PATH):
		return
	_test_pause_and_back_restore_exactly_without_duplicate_events()
	_cleanup()
	_test_stale_checkpoint_replays_the_journal()
	_cleanup()
	_test_equal_sequence_tamper_is_replayed()
	_cleanup()
	_test_checkpoint_ahead_of_journal_is_quarantined()
	_cleanup()
	_test_missing_terminal_completion_is_repaired()
	_cleanup()
	_test_failed_hardware_back_is_consumed()
	_test_completion_deletes_the_checkpoint()
	_cleanup()
	await _test_shell_resumes_through_the_pin_gate(tree)
	_remove_tree(SHELL_BASE_PATH)

func _test_pause_and_back_restore_exactly_without_duplicate_events() -> void:
	var fixture := _fixture()
	var started: Dictionary = fixture.session.start_run(fixture.activity, fixture.question)
	assert_true(started.ok)
	assert_true(fixture.session.submit_answer(fixture.question.correct_answer, 321, 0).ok)
	var next_question: Dictionary = fixture.engine.generate_question(fixture.activity, &"count_to_10", 43)
	assert_true(fixture.session.begin_question(next_question).ok)
	var expected_state: Dictionary = fixture.session.snapshot()
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	lifecycle.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(fixture.journal.flush_calls, 1)
	assert_true(FileAccess.file_exists(_checkpoint_file()))
	lifecycle.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(fixture.journal.flush_calls, 2)
	var event_count_before: int = fixture.journal.replay().events.size()
	lifecycle.free()

	var restored_fixture := _reconstructed_fixture()
	var restored_lifecycle: Node = _new_lifecycle(restored_fixture)
	var restored: Dictionary = restored_lifecycle.restore_if_present()
	assert_true(restored.ok)
	assert_true(restored.restored)
	assert_eq(restored.source, "checkpoint")
	assert_eq(restored.run_session.session_id(), SESSION_ID)
	assert_eq(restored.run_session.snapshot(), expected_state)
	assert_eq(restored.current_question, next_question)
	assert_eq(restored.current_question.seed, 43)
	var replayed_after_restore: Dictionary = restored_fixture.journal.replay()
	assert_eq(replayed_after_restore.events.size(), event_count_before)
	assert_eq(replayed_after_restore.events.map(func(event): return event.event_type), ["run_started", "answer_submitted"])
	assert_true(restored.run_session.submit_answer(99, 400, 0).ok, "the restored run must remain playable")
	assert_eq(restored_fixture.journal.replay().events.size(), event_count_before + 1)
	restored_lifecycle.free()
	fixture.progress.free()
	restored_fixture.progress.free()

func _test_stale_checkpoint_replays_the_journal() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	assert_true(lifecycle.flush_and_checkpoint().ok)
	var stale: Dictionary = fixture.checkpoint_store.load(PROFILE_ID, "a-vertical-1").checkpoint
	assert_eq(stale.last_event_sequence, 1)
	assert_true(fixture.session.submit_answer(fixture.question.correct_answer, 222, 0).ok)
	var next_question: Dictionary = fixture.engine.generate_question(fixture.activity, &"count_to_10", 43)
	assert_true(fixture.session.begin_question(next_question).ok)
	var expected_state: Dictionary = fixture.session.snapshot()
	lifecycle.free()

	var restored_fixture := _reconstructed_fixture()
	var restored_lifecycle: Node = _new_lifecycle(restored_fixture)
	var restored: Dictionary = restored_lifecycle.restore_if_present()
	assert_true(restored.ok)
	assert_eq(restored.source, "journal_replay")
	assert_eq(restored.run_session.snapshot(), expected_state, "stale run_state must not override journal replay")
	assert_eq(restored.current_question.seed, 43)
	assert_eq(restored_fixture.journal.replay().events.size(), 2)
	var refreshed: Dictionary = restored_fixture.checkpoint_store.load(PROFILE_ID, "a-vertical-1")
	assert_true(refreshed.ok)
	assert_eq(refreshed.checkpoint.last_event_sequence, 2)
	assert_eq(refreshed.checkpoint.run_state, expected_state)
	restored_lifecycle.free()
	fixture.progress.free()
	restored_fixture.progress.free()

func _test_completion_deletes_the_checkpoint() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	assert_true(lifecycle.flush_and_checkpoint().ok)
	assert_true(FileAccess.file_exists(_checkpoint_file()))
	var question: Dictionary = fixture.question
	for seed in [42, 43, 44]:
		if seed != 42:
			question = fixture.engine.generate_question(fixture.activity, &"count_to_10", seed)
			assert_true(fixture.session.begin_question(question).ok)
		var submitted: Dictionary = fixture.session.submit_answer(99, 100, 0)
		assert_true(submitted.ok)
	assert_eq(fixture.session.snapshot().status, "completed")
	assert_false(FileAccess.file_exists(_checkpoint_file()), "completed run left a resumable checkpoint")
	assert_eq(lifecycle.flush_and_checkpoint().get("error", ""), "no_active_run")
	lifecycle.free()
	fixture.progress.free()

func _test_failed_hardware_back_is_consumed() -> void:
	var shell: Control = AppShellScene.instantiate()
	var router := ActivityBackRouter.new()
	var lifecycle := CheckpointFailingLifecycle.new()
	shell._router = router
	shell._app_lifecycle = lifecycle
	assert_true(shell.handle_back_navigation(), "failed checkpoint must consume hardware back without quitting")
	assert_eq(lifecycle.flush_calls, 1)
	assert_eq(router.back_calls, 0, "navigation proceeded without a durable checkpoint")
	shell.free()

func _test_checkpoint_ahead_of_journal_is_quarantined() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	assert_true(fixture.session.submit_answer(fixture.question.correct_answer, 100, 0).ok)
	var next_question: Dictionary = fixture.engine.generate_question(fixture.activity, &"count_to_10", 43)
	assert_true(fixture.session.begin_question(next_question).ok)
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	assert_true(lifecycle.flush_and_checkpoint().ok)
	var durable_events: Array = fixture.journal.replay().events
	assert_eq(durable_events.size(), 2)
	lifecycle.free()

	var truncated_fixture := fixture.duplicate(false)
	truncated_fixture.journal = ReplayOverrideJournal.new([durable_events[0]])
	var truncated_lifecycle: Node = _new_lifecycle(truncated_fixture)
	var restored: Dictionary = truncated_lifecycle.restore_if_present()
	assert_false(restored.ok, "a checkpoint newer than the journal must not roll state backward")
	assert_eq(restored.get("error", ""), "checkpoint_ahead_of_journal")
	assert_false(FileAccess.file_exists(_checkpoint_file()))
	assert_true(FileAccess.file_exists("%s.corrupt" % _checkpoint_file()))
	truncated_lifecycle.free()
	fixture.progress.free()

func _test_missing_terminal_completion_is_repaired() -> void:
	var failing_journal := CompletionFailingJournal.new()
	var fixture := _fixture(failing_journal)
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	var question: Dictionary = fixture.question
	for seed in [42, 43]:
		if seed != 42:
			question = fixture.engine.generate_question(fixture.activity, &"count_to_10", seed)
			assert_true(fixture.session.begin_question(question).ok)
		assert_true(fixture.session.submit_answer(99, 100, 0).ok)
	question = fixture.engine.generate_question(fixture.activity, &"count_to_10", 44)
	assert_true(fixture.session.begin_question(question).ok)
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	assert_true(lifecycle.flush_and_checkpoint().ok)
	failing_journal.fail_completion = true
	var interrupted: Dictionary = fixture.session.submit_answer(99, 100, 0)
	assert_false(interrupted.ok)
	assert_eq(fixture.journal.replay().events.map(func(event): return event.event_type), [
		"run_started", "answer_submitted", "answer_submitted", "answer_submitted"
	])
	lifecycle.free()
	fixture.progress.free()

	var restored_fixture := _reconstructed_fixture()
	var durable_progress: Node = restored_fixture.progress
	restored_fixture.progress = FailOnceCompletionProgress.new(durable_progress)
	var restored_lifecycle: Node = _new_lifecycle(restored_fixture)
	var first_restore: Dictionary = restored_lifecycle.restore_if_present()
	assert_false(first_restore.ok, "a failed progress snapshot write must retain the repair checkpoint")
	assert_eq(first_restore.get("error", ""), "completion_repair_progress_failed")
	assert_true(FileAccess.file_exists(_checkpoint_file()))
	var restored: Dictionary = restored_lifecycle.restore_if_present()
	assert_true(restored.ok, "a durable completion repair must be retryable without duplication")
	assert_false(restored.get("restored", true))
	var repaired_events: Array = restored_fixture.journal.replay().events
	assert_eq(repaired_events.map(func(event): return event.event_type), [
		"run_started", "answer_submitted", "answer_submitted", "answer_submitted", "run_completed"
	])
	assert_eq(durable_progress.snapshot().run_totals.health_depleted, 1)
	assert_eq(restored_fixture.checkpoint_store.load(PROFILE_ID).error, "not_found")
	restored_lifecycle.free()
	durable_progress.free()

func _test_equal_sequence_tamper_is_replayed() -> void:
	var fixture := _fixture()
	assert_true(fixture.session.start_run(fixture.activity, fixture.question).ok)
	assert_true(fixture.session.submit_answer(fixture.question.correct_answer, 100, 0).ok)
	var next_question: Dictionary = fixture.engine.generate_question(fixture.activity, &"count_to_10", 43)
	assert_true(fixture.session.begin_question(next_question).ok)
	var expected_state: Dictionary = fixture.session.snapshot()
	var lifecycle: Node = _new_lifecycle(fixture)
	assert_true(lifecycle.bind_active_run(fixture.session, fixture.activity).ok)
	assert_true(lifecycle.flush_and_checkpoint().ok)
	var tampered: Dictionary = fixture.checkpoint_store.load(PROFILE_ID, "a-vertical-1").checkpoint
	tampered.run_state.score = 2
	tampered.run_state.combo = 2
	tampered.run_state.earned_rewards.apples = 999
	assert_true(fixture.checkpoint_store.save(tampered).ok)
	lifecycle.free()
	fixture.progress.free()

	var restored_fixture := _reconstructed_fixture()
	var restored_lifecycle: Node = _new_lifecycle(restored_fixture)
	var restored: Dictionary = restored_lifecycle.restore_if_present()
	assert_true(restored.ok)
	assert_eq(restored.source, "journal_replay")
	assert_eq(restored.state, expected_state, "equal sequence trusted tampered derived run state")
	assert_eq(restored.current_question, next_question)
	restored_lifecycle.free()
	restored_fixture.progress.free()

func _test_shell_resumes_through_the_pin_gate(tree: SceneTree) -> void:
	_remove_tree(SHELL_BASE_PATH)
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new("%s/index" % SHELL_BASE_PATH))
	var created: Dictionary = profile_service.create_profile("다시", "moa_mint", "1357")
	assert_true(created.ok)
	var profile_id: String = created.profile.profile_id
	var first_lifecycle: Node = _shell_lifecycle(profile_id)
	var first_shell: Control = await _mount_shell(tree, profile_service, profile_id, first_lifecycle)
	var profile_screen: Control = _current_screen(first_shell)
	var activation: Dictionary = profile_screen.attempt_unlock(profile_id, "1357", 1000)
	assert_true(activation.ok)
	assert_true(activation.route_params.get("app_lifecycle") == first_lifecycle, "AppShell did not inject lifecycle ownership")
	assert_true(activation.route_params.has("sync_service"), "AppShell did not inject offline sync status")
	if not activation.get("ok", false) or first_shell.current_route() != AppRouteScript.ISLAND:
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return
	var island: Control = _current_screen(first_shell)
	island.open_free_play()
	await tree.process_frame
	var free_play: Control = _current_screen(first_shell)
	free_play.find_child("ActivityButton_0", true, false).accepted.emit()
	await tree.process_frame
	var activity: Control = _current_screen(first_shell)
	activity.skip_introduction()
	var first_question: Dictionary = activity.current_question()
	assert_true(activity.submit_answer(first_question.correct_answer, 150, 0).ok)
	var expected_state: Dictionary = activity.current_state()
	var expected_session_id: String = activity.session_id()
	assert_eq(activity.current_question().seed, 43)
	var back_button: Control = activity.find_child("BackButton", true, false)
	assert_true(back_button != null, "activity back action is missing")
	back_button.accepted.emit()
	await tree.process_frame
	assert_eq(first_shell.current_route(), AppRouteScript.FREE_PLAY)
	assert_eq(first_lifecycle.flush_and_checkpoint().get("error", ""), "no_active_run")
	assert_true(FileAccess.file_exists("%s/profiles/%s/run_checkpoint.json" % [SHELL_BASE_PATH, profile_id]))
	var journal: Variant = activation.journal
	assert_eq(journal.replay().events.size(), 2)
	activation.clear()
	journal = null
	first_shell.queue_free()
	await tree.process_frame

	var second_lifecycle: Node = _shell_lifecycle(profile_id)
	var second_shell: Control = await _mount_shell(tree, profile_service, profile_id, second_lifecycle)
	var restored_profile_screen: Control = _current_screen(second_shell)
	var restored_activation: Dictionary = restored_profile_screen.attempt_unlock(profile_id, "1357", 2000)
	assert_true(restored_activation.ok)
	assert_eq(second_shell.current_route(), AppRouteScript.ACTIVITY_RUN, "checkpoint did not resume after PIN verification")
	await tree.process_frame
	if second_shell.current_route() == AppRouteScript.ACTIVITY_RUN:
		var restored_activity: Control = _current_screen(second_shell)
		assert_eq(restored_activity.session_id(), expected_session_id)
		assert_eq(restored_activity.current_state(), expected_state)
		assert_eq(restored_activity.current_question().seed, 43)
		assert_false(restored_activity.introduction_visible(), "restored run replayed its introduction")
		var replayed: Dictionary = restored_activation.journal.replay()
		assert_eq(replayed.events.size(), 2)
		assert_eq(replayed.events.map(func(event): return event.event_type), ["run_started", "answer_submitted"])
	restored_activation.clear()
	second_shell.queue_free()
	await tree.process_frame
	profile_service.free()
	await tree.process_frame

func _shell_lifecycle(_profile_id: String) -> Node:
	var LifecycleScript: Variant = load(LIFECYCLE_PATH)
	var StoreScript: Variant = load(CHECKPOINT_PATH)
	return LifecycleScript.new(
		StoreScript.new("%s/profiles" % SHELL_BASE_PATH),
		VerticalSliceContentRepositoryScript.new(),
		VerticalSliceQuestionEngineScript.new()
	)

func _mount_shell(tree: SceneTree, profile_service: Node, profile_id: String, lifecycle: Node) -> Control:
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": TestAudioService.new(),
		"effects_service": null,
		"app_lifecycle": lifecycle,
		"progress_factory": func(): return ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/profiles/%s" % [SHELL_BASE_PATH, profile_id])),
		"journal_path_builder": func(candidate_profile_id: String): return "%s/profiles/%s/events.jsonl" % [SHELL_BASE_PATH, candidate_profile_id],
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	return shell

func _current_screen(shell: Control) -> Control:
	return shell.route_host.get_child(shell.route_host.get_child_count() - 1) as Control

func _fixture(journal_override: Variant = null) -> Dictionary:
	var journal: Variant = journal_override if journal_override != null else FlushCountingJournal.new()
	assert_true(journal.configure(PROFILE_ID, DEVICE_ID, _journal_file()).ok)
	var progress := ProgressServiceScript.new(TestStoreFactory.new())
	assert_true(progress.load_profile(PROFILE_ID, journal).ok)
	var repository := VerticalSliceContentRepositoryScript.new()
	var engine := VerticalSliceQuestionEngineScript.new()
	var activity: Dictionary = repository.get_activity(&"foundation_ten_rods")
	var question: Dictionary = engine.generate_question(activity, &"count_to_10", 42)
	var session := RunSessionScript.new(
		null,
		journal,
		progress,
		func(): return "2026-07-22T01:02:03Z",
		func(): return SESSION_ID
	)
	return {
		"activity": activity,
		"checkpoint_store": _new_checkpoint_store(),
		"engine": engine,
		"journal": journal,
		"progress": progress,
		"question": question,
		"repository": repository,
		"router": FakeRouter.new(),
		"session": session,
	}

func _reconstructed_fixture() -> Dictionary:
	var journal := FlushCountingJournal.new()
	assert_true(journal.configure(PROFILE_ID, DEVICE_ID, _journal_file()).ok)
	var progress := ProgressServiceScript.new(TestStoreFactory.new())
	assert_true(progress.load_profile(PROFILE_ID, journal).ok)
	return {
		"checkpoint_store": _new_checkpoint_store(),
		"engine": VerticalSliceQuestionEngineScript.new(),
		"journal": journal,
		"progress": progress,
		"repository": VerticalSliceContentRepositoryScript.new(),
		"router": FakeRouter.new(),
	}

func _new_checkpoint_store() -> Variant:
	var StoreScript: Variant = load(CHECKPOINT_PATH)
	return StoreScript.new(BASE_PATH)

func _new_lifecycle(fixture: Dictionary) -> Node:
	var LifecycleScript: Variant = load(LIFECYCLE_PATH)
	var lifecycle: Node = LifecycleScript.new(fixture.checkpoint_store, fixture.repository, fixture.engine)
	var configured: Dictionary = lifecycle.configure(PROFILE_ID, fixture.journal, fixture.progress, fixture.router)
	assert_true(configured.ok)
	return lifecycle

func _journal_file() -> String:
	return "%s/%s/events.jsonl" % [BASE_PATH, PROFILE_ID]

func _checkpoint_file() -> String:
	return "%s/%s/run_checkpoint.json" % [BASE_PATH, PROFILE_ID]

func _cleanup() -> void:
	_remove_tree("user://tests/lifecycle_resume")

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_tree(child)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)
