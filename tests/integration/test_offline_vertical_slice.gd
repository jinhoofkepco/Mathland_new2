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
const AppShellScene = preload("res://scenes/app/app_shell.tscn")
const ActivityRunScene = preload("res://scenes/game/activity_run.tscn")

const BASE_PATH := "user://tests/offline_vertical_slice"
const DEVICE_ID := "da640863-b3af-4ca2-8e27-e474831b57ed"
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
	_remove_tree(BASE_PATH)
	var profile_store := AtomicJsonStoreScript.new("%s/profile_index" % BASE_PATH)
	var profile_service := ProfileServiceScript.new(profile_store)
	var created := profile_service.create_profile("별이", "moa_sky", "2468")
	assert_true(created.ok)
	var profile_id: String = created.profile.profile_id
	var journal_path := "%s/%s/events.jsonl" % [BASE_PATH, profile_id]
	var response_clock := FakeClockScript.new(10_000)
	var shell := await _mount_shell(tree, profile_service, profile_id, response_clock)
	assert_eq(shell.current_route(), AppRouteScript.PROFILE_SELECT, "cold boot bypassed PIN selection")
	var profile_screen: Control = _current_screen(shell)
	var activation: Dictionary = profile_screen.attempt_unlock(profile_id, "2468", 1000)
	assert_true(activation.ok)
	var journal: Variant = activation.get("journal")
	var progress: Variant = activation.get("progress_service")
	assert_true(journal.get_script() == EventJournalScript, "activation must inject a real EventJournal")
	assert_true(progress.get_script() == ProgressServiceScript, "activation must inject a real ProgressService")
	assert_eq(progress.snapshot().profile_id, profile_id)
	assert_eq(progress.snapshot().last_sequence, 0, "injected progress was not loaded against its journal")
	assert_eq(activation.route_params.journal, journal)
	assert_eq(activation.route_params.progress_service, progress)
	assert_false(activation.route_params.has("run_session"), "AppShell must leave per-run construction to ActivityRun")
	assert_eq(shell.current_route(), AppRouteScript.ISLAND)
	await tree.process_frame
	var island: Control = _current_screen(shell)
	island.open_free_play()
	assert_eq(shell.current_route(), AppRouteScript.FREE_PLAY)
	await tree.process_frame
	var free_play: Control = _current_screen(shell)
	var activity_button: Control = free_play.find_child("ActivityButton_0", true, false)
	activity_button.accepted.emit()
	assert_eq(shell.current_route(), AppRouteScript.ACTIVITY_RUN)
	await tree.process_frame
	var activity: Control = _current_screen(shell)
	assert_true(activity.introduction_visible())
	assert_false(activity.can_answer())
	activity.skip_introduction()
	assert_true(activity.can_answer(), "the skippable introduction must never block after skip")
	var speaker: Control = activity.find_child("SpeakerButton", true, false)
	assert_not_null(speaker)
	assert_true(speaker.is_visible_in_tree())
	var first_session_id: String = activity.session_id()
	assert_false(first_session_id.is_empty(), "ActivityRun did not construct its RunSession from activated dependencies")
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
		if index == 1:
			await _assert_persisted_reward_presets(tree, activity, journal, progress)

	assert_eq(activity.current_state().health, 0)
	assert_eq(activity.current_state().completion_reason, "health_depleted")
	assert_eq(progress.snapshot().apples, 4)
	assert_eq(progress.snapshot().pending_review, 3)
	assert_eq(shell.current_route(), AppRouteScript.RESULT)
	var result: Control = _current_screen(shell)
	assert_eq(result.reason(), "health_depleted")
	assert_eq(result.earned_apples(), 4)
	assert_eq(result.pending_review(), 3)
	result.restart()
	assert_eq(shell.current_route(), AppRouteScript.ACTIVITY_RUN)
	await tree.process_frame
	var restarted: Control = _current_screen(shell)
	assert_ne(restarted.session_id(), first_session_id)
	assert_eq(restarted.pinned_content_version(), "a-vertical-1")

	activation.clear()
	journal = null
	progress = null
	shell.queue_free()
	await tree.process_frame
	var restored_shell := await _mount_shell(tree, profile_service, profile_id, FakeClockScript.new(20_000))
	assert_eq(restored_shell.current_route(), AppRouteScript.PROFILE_SELECT, "restart bypassed the PIN gate")
	var restored_profile_screen: Control = _current_screen(restored_shell)
	var restored_activation: Dictionary = restored_profile_screen.attempt_unlock(profile_id, "2468", 2000)
	assert_true(restored_activation.ok)
	assert_true(restored_activation.journal.get_script() == EventJournalScript)
	assert_true(restored_activation.progress_service.get_script() == ProgressServiceScript)
	assert_eq(restored_activation.snapshot.profile_id, profile_id)
	await tree.process_frame
	var restored_island: Control = _current_screen(restored_shell)
	assert_eq(restored_island.apple_balance(), 4)
	assert_eq(restored_island.pending_review_count(), 3)
	restored_activation.clear()
	restored_shell.queue_free()
	await tree.process_frame
	await _test_activity_persistence_failure_lock(tree, ContentRepositoryScript.new(), QuestionEngineScript.new())
	profile_service.free()
	await tree.process_frame
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(journal_path + ".partial.corrupt")))
	_remove_tree(BASE_PATH)

func _assert_persisted_reward_presets(tree: SceneTree, activity: Control, journal: RefCounted, progress: Node) -> void:
	var collection_append: Dictionary = journal.append({
		"client_timestamp": "2026-07-21T00:00:40Z",
		"event_type": "collection_unlocked",
		"collection_id": "ten_rod_cartographer",
	})
	assert_true(collection_append.ok)
	assert_false(activity.present_persisted_reward_event(collection_append.event), "journal-only reward advanced presentation before progress commit")
	assert_eq(progress.commit(collection_append.event), OK)
	assert_true(activity.present_persisted_reward_event(collection_append.event))
	var collection_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(collection_overlay)
	assert_eq(collection_overlay.preset_kind(), "collection")
	collection_overlay.dismiss()
	await tree.process_frame
	_assert_reward_sequence_fail_closed(activity, collection_append.event)
	var duplicate_collection_append: Dictionary = journal.append({
		"client_timestamp": "2026-07-21T00:00:41Z",
		"event_type": "collection_unlocked",
		"collection_id": "ten_rod_cartographer",
	})
	assert_true(duplicate_collection_append.ok)
	var collection_presentations := 0
	var collection_before_commit: bool = activity.present_persisted_reward_event(duplicate_collection_append.event)
	collection_presentations += 1 if collection_before_commit else 0
	assert_false(collection_before_commit, "a repeated collection ID bypassed its event sequence commit")
	if collection_before_commit:
		var premature_collection: Control = activity.find_child("RewardOverlay", true, false)
		if premature_collection != null:
			premature_collection.dismiss()
			await tree.process_frame
	assert_eq(progress.commit(duplicate_collection_append.event), OK)
	var collection_after_commit: bool = activity.present_persisted_reward_event(duplicate_collection_append.event)
	collection_presentations += 1 if collection_after_commit else 0
	assert_true(collection_after_commit)
	assert_eq(collection_presentations, 1, "a repeated collection reward was not presented exactly once after commit")
	var duplicate_collection_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(duplicate_collection_overlay)
	assert_eq(duplicate_collection_overlay.preset_kind(), "collection")
	duplicate_collection_overlay.dismiss()
	await tree.process_frame
	var coupon_append: Dictionary = journal.append({
		"client_timestamp": "2026-07-21T00:00:42Z",
		"event_type": "coupon_earned",
		"coupon_id": "island_ferry_pass",
	})
	assert_true(coupon_append.ok)
	assert_eq(progress.commit(coupon_append.event), OK)
	var forged_coupon: Dictionary = coupon_append.event.duplicate(true)
	forged_coupon.coupon_id = "forged_coupon"
	assert_false(activity.present_persisted_reward_event(forged_coupon), "an event absent from the durable journal reached presentation")
	assert_true(activity.present_persisted_reward_event(coupon_append.event))
	var coupon_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(coupon_overlay)
	assert_eq(coupon_overlay.preset_kind(), "coupon")
	coupon_overlay.dismiss()
	await tree.process_frame
	_assert_reward_sequence_fail_closed(activity, coupon_append.event)
	var duplicate_coupon_append: Dictionary = journal.append({
		"client_timestamp": "2026-07-21T00:00:43Z",
		"event_type": "coupon_earned",
		"coupon_id": "island_ferry_pass",
	})
	assert_true(duplicate_coupon_append.ok)
	var coupon_presentations := 0
	var coupon_before_commit: bool = activity.present_persisted_reward_event(duplicate_coupon_append.event)
	coupon_presentations += 1 if coupon_before_commit else 0
	assert_false(coupon_before_commit, "a repeated coupon ID bypassed its event sequence commit")
	if coupon_before_commit:
		var premature_coupon: Control = activity.find_child("RewardOverlay", true, false)
		if premature_coupon != null:
			premature_coupon.dismiss()
			await tree.process_frame
	assert_eq(progress.commit(duplicate_coupon_append.event), OK)
	var coupon_after_commit: bool = activity.present_persisted_reward_event(duplicate_coupon_append.event)
	coupon_presentations += 1 if coupon_after_commit else 0
	assert_true(coupon_after_commit)
	assert_eq(coupon_presentations, 1, "a repeated coupon reward was not presented exactly once after commit")
	var duplicate_coupon_overlay: Control = activity.find_child("RewardOverlay", true, false)
	assert_not_null(duplicate_coupon_overlay)
	assert_eq(duplicate_coupon_overlay.preset_kind(), "coupon")
	duplicate_coupon_overlay.dismiss()
	await tree.process_frame

func _assert_reward_sequence_fail_closed(activity: Control, event: Dictionary) -> void:
	var missing_sequence := event.duplicate(true)
	missing_sequence.erase("sequence")
	assert_false(activity.call("_reward_event_is_reduced", missing_sequence), "missing reward sequence did not fail closed")
	for invalid_sequence in [null, true, "1", 0, -1, 1.5, INF, 9007199254740992]:
		var invalid_event := event.duplicate(true)
		invalid_event["sequence"] = invalid_sequence
		assert_false(
			activity.call("_reward_event_is_reduced", invalid_event),
			"invalid reward sequence did not fail closed: %s" % invalid_sequence,
		)

func _mount_shell(tree: SceneTree, profile_service: Node, profile_id: String, response_clock: RefCounted) -> Control:
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": TestAudioService.new(),
		"effects_service": null,
		"progress_factory": func(): return ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/%s" % [BASE_PATH, profile_id])),
		"journal_path_builder": func(candidate_profile_id: String): return "%s/%s/events.jsonl" % [BASE_PATH, candidate_profile_id],
		"response_clock": response_clock,
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	return shell

func _current_screen(shell: Control) -> Control:
	return shell.route_host.get_child(shell.route_host.get_child_count() - 1) as Control

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
