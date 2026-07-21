extends "res://tests/support/test_case.gd"

const AppRouteScript = preload("res://src/app/app_route.gd")
const AppShellScene = preload("res://scenes/app/app_shell.tscn")
const AtomicJsonStoreScript = preload("res://src/persistence/atomic_json_store.gd")
const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const ProfileServiceScript = preload("res://src/profiles/profile_service.gd")
const ProgressServiceScript = preload("res://src/progress/progress_service.gd")

const BASE_PATH := "user://tests/default_runtime_catalogue"
const CHECKPOINT_ROOT := "user://profiles"
const DEVICE_ID := "8aa406ed-b03d-4f38-9873-71ccbf3f4f1c"
const EXPECTED_ACTIVITY_IDS := [
	"addition_ones",
	"subtraction_ones",
	"multiplication",
	"common_multiples_lcm",
	"prime_factorization",
	"foundations_counting",
	"foundations_number_bonds",
	"foundations_ten_frame",
	"foundations_base_ten",
	"foundations_number_line",
	"foundations_basic_operations",
]

class QuietAudioService extends Node:
	func apply_settings(_settings: Dictionary) -> bool:
		return true

	func play_sfx(_sfx_id: StringName) -> bool:
		return true

	func play_music(_music_id: StringName) -> bool:
		return true

	func stop_voice() -> void:
		pass

	func dialogue_for_activity(_activity: Dictionary) -> StringName:
		return &""

	func dialogue_for_policy(_policy: StringName, _context: Dictionary = {}) -> StringName:
		return &""

	func toggle_voice(_dialogue_id: StringName) -> bool:
		return false

	func play_policy_voice(_policy: StringName, _context: Dictionary = {}, _authorized := false) -> bool:
		return false

class PassiveLifecycle extends Node:
	func configure(_profile_id: String, _journal: Variant, _progress: Variant, _router: Variant = null) -> Dictionary:
		return {"ok": true}

	func restore_if_present() -> Dictionary:
		return {"ok": true, "restored": false}

func run(tree: SceneTree) -> void:
	_remove_tree(BASE_PATH)
	await _test_default_shell_catalogue_questions_and_restore(tree)
	await _test_failed_default_initialization_is_diagnostic_and_empty(tree)
	_remove_tree(BASE_PATH)

func _test_default_shell_catalogue_questions_and_restore(tree: SceneTree) -> void:
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new("%s/profiles" % BASE_PATH))
	var created: Dictionary = profile_service.create_profile("카탈로그", "moa_mint", "2468")
	assert_true(created.ok)
	if not created.get("ok", false):
		profile_service.free()
		return
	var profile_id: String = created.profile.profile_id
	_remove_tree("%s/%s" % [CHECKPOINT_ROOT, profile_id])

	var first_shell: Control = await _mount_default_shell(tree, profile_service, profile_id)
	var profile_screen: Control = _current_screen(first_shell)
	var boot_params: Dictionary = profile_screen.get("_params")
	var repository: Variant = boot_params.get("content_repository")
	var question_engine: Variant = boot_params.get("question_engine")
	var lifecycle: Variant = boot_params.get("app_lifecycle")
	assert_true(repository != null and repository.get_script() == ContentRepositoryScript, "default AppShell did not use ContentRepository")
	assert_eq(repository.get_manifest_version() if repository != null else "", "1.0.0")
	assert_true(lifecycle != null and lifecycle.get("_content_repository") == repository, "AppLifecycle did not receive the AppShell repository instance")
	assert_true(question_engine != null and lifecycle != null and lifecycle.get("_question_engine") == question_engine, "AppLifecycle did not receive the AppShell question engine instance")

	var activation: Dictionary = profile_screen.attempt_unlock(profile_id, "2468", 1000)
	assert_true(activation.ok)
	assert_eq(first_shell.current_route(), AppRouteScript.ISLAND)
	await tree.process_frame
	var island: Control = _current_screen(first_shell)
	island.open_free_play()
	await tree.process_frame
	var free_play: Control = _current_screen(first_shell)
	var activities: Array[Dictionary] = free_play.activities()
	assert_eq(activities.map(func(activity): return activity.get("activity_id")), EXPECTED_ACTIVITY_IDS)
	assert_eq(activities.size(), 11)

	if not _open_activity(free_play, activities, "multiplication"):
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return
	await tree.process_frame
	assert_eq(first_shell.current_route(), AppRouteScript.ACTIVITY_RUN)
	if first_shell.current_route() != AppRouteScript.ACTIVITY_RUN:
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return
	var multiplication_run: Control = _current_screen(first_shell)
	var multiplication_question: Dictionary = multiplication_run.current_question()
	assert_eq(multiplication_question.get("activity_id"), "multiplication")
	assert_eq(multiplication_question.get("generator_id"), "multiplication_v1")
	assert_false(multiplication_question.is_empty(), "multiplication did not generate through the default AppShell")
	assert_true(lifecycle.release_active_run().get("ok", false))
	var router: Variant = first_shell.get("_router")
	assert_true(router != null and router.back())
	await tree.process_frame
	assert_eq(first_shell.current_route(), AppRouteScript.FREE_PLAY)
	if first_shell.current_route() != AppRouteScript.FREE_PLAY:
		activation.clear()
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return

	free_play = _current_screen(first_shell)
	activities = free_play.activities()
	if not _open_activity(free_play, activities, "foundations_number_line"):
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return
	await tree.process_frame
	assert_eq(first_shell.current_route(), AppRouteScript.ACTIVITY_RUN)
	if first_shell.current_route() != AppRouteScript.ACTIVITY_RUN:
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		return
	var number_line_run: Control = _current_screen(first_shell)
	var expected_session_id: String = number_line_run.session_id()
	var expected_state: Dictionary = number_line_run.current_state()
	var expected_question: Dictionary = number_line_run.current_question()
	assert_eq(expected_question.get("activity_id"), "foundations_number_line")
	assert_eq(expected_question.get("generator_id"), "number_line_v1")
	assert_eq(expected_question.get("manipulative", {}).get("id"), "number_line")
	assert_true(first_shell.handle_back_navigation(), "number-line run did not checkpoint on back")
	await tree.process_frame
	assert_eq(first_shell.current_route(), AppRouteScript.FREE_PLAY, "number-line checkpoint did not permit navigation")
	assert_true(FileAccess.file_exists("%s/%s/run_checkpoint.json" % [CHECKPOINT_ROOT, profile_id]))
	if first_shell.current_route() != AppRouteScript.FREE_PLAY:
		activation.clear()
		first_shell.queue_free()
		await tree.process_frame
		profile_service.free()
		await tree.process_frame
		_remove_tree("%s/%s" % [CHECKPOINT_ROOT, profile_id])
		return

	activation.clear()
	first_shell.queue_free()
	await tree.process_frame
	var second_shell: Control = await _mount_default_shell(tree, profile_service, profile_id)
	var restored_profile_screen: Control = _current_screen(second_shell)
	var restored_activation: Dictionary = restored_profile_screen.attempt_unlock(profile_id, "2468", 2000)
	assert_true(restored_activation.ok)
	assert_eq(second_shell.current_route(), AppRouteScript.ACTIVITY_RUN, "non-ten-rod checkpoint did not resume")
	await tree.process_frame
	if second_shell.current_route() == AppRouteScript.ACTIVITY_RUN:
		var restored_run: Control = _current_screen(second_shell)
		assert_eq(restored_run.session_id(), expected_session_id)
		assert_eq(restored_run.current_state(), expected_state)
		assert_eq(restored_run.current_question(), expected_question)
		assert_eq(restored_run.current_question().get("generator_id"), "number_line_v1")
		assert_false(restored_run.introduction_visible(), "restored non-ten-rod run replayed its introduction")
		assert_true(second_shell.handle_back_navigation())
		await tree.process_frame
	restored_activation.clear()
	second_shell.queue_free()
	await tree.process_frame
	profile_service.free()
	await tree.process_frame
	_remove_tree("%s/%s" % [CHECKPOINT_ROOT, profile_id])

func _test_failed_default_initialization_is_diagnostic_and_empty(tree: SceneTree) -> void:
	var profile_service := ProfileServiceScript.new(AtomicJsonStoreScript.new("%s/fail_profiles" % BASE_PATH))
	var created: Dictionary = profile_service.create_profile("빈섬", "moa_sky", "1357")
	assert_true(created.ok)
	if not created.get("ok", false):
		profile_service.free()
		return
	var profile_id: String = created.profile.profile_id
	var diagnostics: Array[String] = []
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.has_signal("diagnostic"), "AppShell has no content initialization diagnostic")
	if shell.has_signal("diagnostic"):
		shell.connect("diagnostic", func(code: String): diagnostics.append(code))
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": QuietAudioService.new(),
		"effects_service": null,
		"app_lifecycle": PassiveLifecycle.new(),
		"content_manifest_path": "res://content/missing-release-manifest.json",
		"content_cache_root": "%s/missing-cache" % BASE_PATH,
		"progress_factory": func(): return ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/fail_progress/%s" % [BASE_PATH, profile_id])),
		"journal_path_builder": func(candidate_profile_id: String): return "%s/fail_journal/%s/events.jsonl" % [BASE_PATH, candidate_profile_id],
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	assert_true("content_initialization_failed" in diagnostics, "missing bundled content did not emit a diagnostic")
	var profile_screen: Control = _current_screen(shell)
	var activation: Dictionary = profile_screen.attempt_unlock(profile_id, "1357", 1000)
	assert_true(activation.ok)
	await tree.process_frame
	var island: Control = _current_screen(shell)
	island.open_free_play()
	await tree.process_frame
	var free_play: Control = _current_screen(shell)
	assert_eq(free_play.activities(), [], "failed content initialization fell back to playable stale content")
	assert_not_null(free_play.find_child("FreePlayEmpty", true, false), "failed content initialization did not render the safe empty state")
	activation.clear()
	shell.queue_free()
	await tree.process_frame
	profile_service.free()
	await tree.process_frame

func _mount_default_shell(tree: SceneTree, profile_service: Node, profile_id: String) -> Control:
	var shell: Control = AppShellScene.instantiate()
	assert_true(shell.configure_dependencies({
		"profile_service": profile_service,
		"device_id": DEVICE_ID,
		"audio_service": QuietAudioService.new(),
		"effects_service": null,
		"content_cache_root": "%s/content-cache" % BASE_PATH,
		"progress_factory": func(): return ProgressServiceScript.new(AtomicJsonStoreScript.new("%s/progress/%s" % [BASE_PATH, profile_id])),
		"journal_path_builder": func(candidate_profile_id: String): return "%s/journal/%s/events.jsonl" % [BASE_PATH, candidate_profile_id],
	}))
	tree.root.add_child(shell)
	await tree.process_frame
	return shell

func _open_activity(free_play: Control, activities: Array[Dictionary], activity_id: String) -> bool:
	var index := -1
	for candidate_index in activities.size():
		if activities[candidate_index].get("activity_id") == activity_id:
			index = candidate_index
			break
	assert_true(index >= 0, "%s is missing from FreePlay" % activity_id)
	if index < 0:
		return false
	var button: Control = free_play.find_child("ActivityButton_%d" % index, true, false)
	assert_not_null(button, "%s has no activity button" % activity_id)
	if button != null:
		button.accepted.emit()
		return true
	return false

func _current_screen(shell: Control) -> Control:
	return shell.route_host.get_child(shell.route_host.get_child_count() - 1) as Control

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
