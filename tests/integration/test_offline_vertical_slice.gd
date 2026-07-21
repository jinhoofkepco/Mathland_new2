extends "res://tests/support/test_case.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const EventJournalScript = preload("res://src/persistence/event_journal.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")
const RunSessionScript = preload("res://src/game/run_session.gd")
const ContentRepositoryScript = preload("res://src/content/vertical_slice_content_repository.gd")
const QuestionEngineScript = preload("res://src/content/vertical_slice_question_engine.gd")
const FakeClockScript = preload("res://tests/support/fake_clock.gd")
const InMemoryProgressServiceScript = preload("res://tests/support/in_memory_progress_service.gd")
const RecordingJournalScript = preload("res://tests/support/recording_journal.gd")
const ProfileSelectScene = preload("res://scenes/profile/profile_select.tscn")
const IslandScene = preload("res://scenes/island/exploration_island.tscn")
const FreePlayScene = preload("res://scenes/island/free_play.tscn")
const ActivityRunScene = preload("res://scenes/game/activity_run.tscn")
const RunResultScene = preload("res://scenes/game/run_result.tscn")

const BASE_PATH := "user://tests/offline_vertical_slice"
const DEVICE_ID := "test-device"
const MAX_RESPONSE_DURATION_MS := 86_400_000

class RecordingRouter extends RefCounted:
	var calls: Array[Dictionary] = []

	func navigate(route: StringName, params: Dictionary = {}) -> Dictionary:
		calls.append({"mode": "navigate", "route": route, "params": params.duplicate(false)})
		return {"ok": true}

	func replace(route: StringName, params: Dictionary = {}) -> Dictionary:
		calls.append({"mode": "replace", "route": route, "params": params.duplicate(false)})
		return {"ok": true}

	func back() -> bool:
		return true

func run(tree: SceneTree) -> void:
	_remove_tree(BASE_PATH)
	var profile_store := AtomicJsonStoreScript.new("%s/profile_index" % BASE_PATH)
	var profile_service := ProfileServiceScript.new(profile_store)
	var created := profile_service.create_profile("별이", "moa_sky", "2468")
	assert_true(created.ok)
	var profile_id: String = created.profile.profile_id
	var journal_path := "%s/%s/events.jsonl" % [BASE_PATH, profile_id]
	var journal := EventJournalScript.new()
	assert_true(journal.configure(profile_id, DEVICE_ID, journal_path).ok)
	var progress_store := AtomicJsonStoreScript.new("%s/%s" % [BASE_PATH, profile_id])
	var progress := ProgressServiceScript.new(progress_store)
	assert_true(progress.load_profile(profile_id, journal).ok)
	var repository := ContentRepositoryScript.new()
	var question_engine := QuestionEngineScript.new()
	var router := RecordingRouter.new()
	var timestamp_counter := {"value": 0}
	var session_counter := {"value": 0}
	var timestamp_provider := func() -> String:
		timestamp_counter.value += 1
		return "2026-07-21T00:00:%02dZ" % timestamp_counter.value
	var run_session := RunSessionScript.new(
		null,
		journal,
		progress,
		timestamp_provider,
		func() -> String:
			session_counter.value += 1
			return "offline-session-%d" % session_counter.value
	)
	assert_true(journal.get_script() == EventJournalScript, "activation must inject a real EventJournal")
	assert_true(progress.get_script() == ProgressServiceScript, "activation must inject a real ProgressService")
	assert_eq(progress.snapshot().profile_id, profile_id)
	assert_eq(progress.snapshot().last_sequence, 0, "injected progress was not loaded against its journal")
	var shared_params := {
		"router": router,
		"profile_service": profile_service,
		"progress_service": progress,
		"content_repository": repository,
		"audio_service": null,
		"effects_service": null,
		"profile_id": profile_id,
		"date": "2026-07-21",
		"online": false,
		"sync_queue_count": 0,
	}

	var profile_screen := await _mount(tree, ProfileSelectScene, shared_params)
	assert_true(profile_screen.attempt_unlock(profile_id, "2468", 1000).ok)
	assert_eq(router.calls.back().route, AppRouteScript.ISLAND)
	var island := await _mount(tree, IslandScene, shared_params)
	island.open_free_play()
	assert_eq(router.calls.back().route, AppRouteScript.FREE_PLAY)
	var free_play := await _mount(tree, FreePlayScene, shared_params)
	var activity_button: Control = free_play.find_child("ActivityButton_0", true, false)
	activity_button.accepted.emit()
	assert_eq(router.calls.back().route, AppRouteScript.ACTIVITY_RUN)
	var activity_params: Dictionary = router.calls.back().params.duplicate(false)
	activity_params["journal"] = journal
	activity_params["progress_service"] = progress
	activity_params["question_engine"] = question_engine
	activity_params["run_session"] = run_session
	activity_params["seed"] = 42
	var response_clock := FakeClockScript.new(10_000)
	activity_params["response_clock"] = response_clock
	var activity := await _mount(tree, ActivityRunScene, activity_params)
	assert_true(activity.introduction_visible())
	assert_false(activity.can_answer())
	activity.skip_introduction()
	assert_true(activity.can_answer(), "the skippable introduction must never block after skip")
	var speaker: Control = activity.find_child("SpeakerButton", true, false)
	assert_not_null(speaker)
	assert_true(speaker.is_visible_in_tree())
	var first_session_id: String = activity.session_id()
	assert_eq(first_session_id, "offline-session-1")
	assert_eq(activity.pinned_content_version(), "a-vertical-1")
	var expected_answer_event_count := 0
	var answer_counts_when_presented: Array[int] = []
	activity.question_presented.connect(func(_question: Dictionary):
		var presentation_replay: Dictionary = journal.replay()
		var durable_answers: Array = presentation_replay.events.filter(func(event): return event.event_type == "answer_submitted")
		answer_counts_when_presented.append(durable_answers.size())
	)
	for index in 5:
		var question: Dictionary = activity.current_question()
		var seed_before: int = question.seed
		var answer: int = int(question.correct_answer) if index < 2 else int(question.correct_answer) + 1
		if index < 2:
			response_clock.advance_ms(345 if index == 0 else MAX_RESPONSE_DURATION_MS + 500)
			var board: Control = activity.find_child("TenRodBoard", true, false)
			board.apply_answer_state(_ten_rod_state(answer))
			board.submit_current_answer()
		else:
			var submitted: Dictionary = activity.submit_answer(answer, 120 + index)
			assert_true(submitted.ok)
		expected_answer_event_count += 1
		var replayed: Dictionary = journal.replay()
		var answer_events: Array = replayed.events.filter(func(event): return event.event_type == "answer_submitted")
		assert_eq(answer_events.size(), expected_answer_event_count, "UI advanced before durable answer append")
		assert_eq(answer_events.back().submitted_answer, answer)
		if index == 0:
			assert_eq(answer_events.back().response_duration_ms, 345, "real board input did not use the monotonic question tick")
		elif index == 1:
			assert_eq(answer_events.back().response_duration_ms, MAX_RESPONSE_DURATION_MS, "response duration was not bounded")
		if index < 4:
			assert_eq(answer_counts_when_presented.back(), expected_answer_event_count, "next question appeared before durable append")
			assert_ne(activity.current_question().seed, seed_before)
		if index < 2:
			var reward_overlay: Control = activity.find_child("RewardOverlay", true, false)
			assert_not_null(reward_overlay)
			assert_not_null(reward_overlay.find_child("SkipRewardButton", true, false))
			assert_true(reward_overlay.has_method("preset_kind"), "RewardOverlay must expose its resolved preset")
			if reward_overlay.has_method("preset_kind"):
				assert_eq(reward_overlay.preset_kind(), "reward")
			reward_overlay.dismiss()
			await tree.process_frame

	assert_eq(activity.current_state().health, 0)
	assert_eq(activity.current_state().completion_reason, "health_depleted")
	assert_eq(progress.snapshot().apples, 4)
	assert_eq(progress.snapshot().pending_review, 3)
	assert_eq(router.calls.back().mode, "replace")
	assert_eq(router.calls.back().route, AppRouteScript.RESULT)
	var result_params: Dictionary = router.calls.back().params.duplicate(false)
	var result := await _mount(tree, RunResultScene, result_params)
	assert_eq(result.reason(), "health_depleted")
	assert_eq(result.earned_apples(), 4)
	assert_eq(result.pending_review(), 3)
	var collection_append: Dictionary = journal.append({
		"client_timestamp": timestamp_provider.call(),
		"event_type": "collection_unlocked",
		"collection_id": "ten_rod_cartographer",
	})
	assert_true(collection_append.ok)
	assert_true(activity.has_method("present_persisted_reward_event"), "ActivityRun must accept committed reward events")
	if activity.has_method("present_persisted_reward_event"):
		assert_false(activity.present_persisted_reward_event(collection_append.event), "journal-only reward advanced presentation before progress commit")
	assert_eq(progress.commit(collection_append.event), OK)
	if activity.has_method("present_persisted_reward_event"):
		assert_true(activity.present_persisted_reward_event(collection_append.event))
	var collection_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(collection_overlay)
	if collection_overlay != null and collection_overlay.has_method("preset_kind"):
		assert_eq(collection_overlay.preset_kind(), "collection")
	if collection_overlay != null:
		collection_overlay.dismiss()
		await tree.process_frame
	var coupon_append: Dictionary = journal.append({
		"client_timestamp": timestamp_provider.call(),
		"event_type": "coupon_earned",
		"coupon_id": "island_ferry_pass",
	})
	assert_true(coupon_append.ok)
	assert_eq(progress.commit(coupon_append.event), OK)
	var forged_coupon: Dictionary = coupon_append.event.duplicate(true)
	forged_coupon.coupon_id = "forged_coupon"
	if activity.has_method("present_persisted_reward_event"):
		assert_false(activity.present_persisted_reward_event(forged_coupon), "an event absent from the durable journal reached presentation")
		assert_true(activity.present_persisted_reward_event(coupon_append.event))
	var coupon_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(coupon_overlay)
	if coupon_overlay != null and coupon_overlay.has_method("preset_kind"):
		assert_eq(coupon_overlay.preset_kind(), "coupon")
	if coupon_overlay != null:
		coupon_overlay.dismiss()
		await tree.process_frame
	result.restart()
	assert_eq(router.calls.back().route, AppRouteScript.ACTIVITY_RUN)
	var restart_params: Dictionary = router.calls.back().params.duplicate(false)
	assert_eq(restart_params.content_version, "a-vertical-1")
	var restarted := await _mount(tree, ActivityRunScene, restart_params)
	assert_ne(restarted.session_id(), first_session_id)
	assert_eq(restarted.pinned_content_version(), "a-vertical-1")

	for node in [profile_screen, island, free_play, activity, result, restarted]:
		node.queue_free()
	await tree.process_frame
	var restarted_journal := EventJournalScript.new()
	assert_true(restarted_journal.configure(profile_id, DEVICE_ID, journal_path).ok)
	var restarted_progress := ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/%s" % [BASE_PATH, profile_id]))
	assert_true(restarted_progress.load_profile(profile_id, restarted_journal).ok)
	var restarted_island_params := shared_params.duplicate(false)
	restarted_island_params["progress_service"] = restarted_progress
	var restored_island := await _mount(tree, IslandScene, restarted_island_params)
	assert_eq(restored_island.apple_balance(), 4)
	assert_eq(restored_island.pending_review_count(), 3)
	restored_island.queue_free()
	await tree.process_frame
	await _test_activity_persistence_failure_lock(tree, repository, question_engine)
	router.calls.clear()
	shared_params.clear()
	activity_params.clear()
	result_params.clear()
	restart_params.clear()
	restarted_island_params.clear()
	profile_service.free()
	progress.free()
	restarted_progress.free()
	await tree.process_frame
	_remove_tree(BASE_PATH)

func _test_activity_persistence_failure_lock(tree: SceneTree, repository: RefCounted, question_engine: RefCounted) -> void:
	for case in [
		{"name": "retry safe", "error": "disk_full", "expected_enabled": true, "expected_blocked": false},
		{"name": "fail stop", "error": "append_recovery_required", "expected_enabled": false, "expected_blocked": true},
	]:
		var operations: Array[String] = []
		var journal := RecordingJournalScript.new("failure-profile", "failure-device", operations)
		var progress := InMemoryProgressServiceScript.new("failure-profile", operations)
		var session := RunSessionScript.new(
			null,
			journal,
			progress,
			func() -> String: return "2026-07-21T01:00:00Z",
			func() -> String: return "failure-session-%s" % case.name
		)
		var activity := await _mount(tree, ActivityRunScene, {
			"router": RecordingRouter.new(),
			"progress_service": progress,
			"content_repository": repository,
			"profile_id": "failure-profile",
			"journal": journal,
			"question_engine": question_engine,
			"run_session": session,
			"activity_id": "foundation_ten_rods",
			"content_version": "a-vertical-1",
			"seed": 42,
			"response_clock": FakeClockScript.new(1000),
		})
		activity.skip_introduction()
		journal.fail_next_error = case.error
		var failed: Dictionary = activity.submit_answer(activity.current_question().correct_answer, 50)
		assert_false(failed.ok, case.name)
		assert_true(session.has_method("is_blocked"), "RunSession must expose fail-stop state")
		if session.has_method("is_blocked"):
			assert_eq(session.is_blocked(), case.expected_blocked, case.name)
		assert_eq(activity.can_answer(), case.expected_enabled, case.name)
		var board: Control = activity.find_child("TenRodBoard", true, false)
		assert_eq(board.add_unit(), case.expected_enabled, "%s board interaction state" % case.name)
		activity.queue_free()
		await tree.process_frame

func _ten_rod_state(value: int) -> Dictionary:
	return {"tens": floori(float(value) / 10.0), "units": value % 10, "value": value}

func _mount(tree: SceneTree, packed: PackedScene, params: Dictionary) -> Control:
	var viewport := tree.root
	var screen: Control = packed.instantiate()
	if screen.has_method("configure"):
		screen.configure(params)
	viewport.add_child(screen)
	await tree.process_frame
	return screen

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	_remove_directory_contents(absolute)
	DirAccess.remove_absolute(absolute)

func _remove_directory_contents(absolute: String) -> void:
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := absolute.path_join(entry)
			if directory.current_is_dir():
				_remove_directory_contents(child_path)
				DirAccess.remove_absolute(child_path)
			else:
				DirAccess.remove_absolute(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
