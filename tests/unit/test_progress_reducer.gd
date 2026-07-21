extends "res://tests/support/test_case.gd"

const LearningEventV1 = preload("res://src/events/learning_event_v1.gd")
const ProgressReducer = preload("res://src/progress/progress_reducer.gd")

const PROFILE_ID := "profile-a"
const DEVICE_ID := "device-a"
const ACTIVITY_ID := "foundation_ten_rods"
const MAX_SAFE_INTEGER := 9007199254740991

func run(_tree: SceneTree) -> void:
	_test_initial_schema_is_exact_and_isolated()
	_test_answers_and_health_depletion_preserve_rewards()
	_test_completion_inventory_collections_and_coupons()
	_test_duplicate_older_wrong_profile_and_invalid_events_are_ignored_copies()
	_test_safe_integer_overflow_does_not_advance()
	_test_repeated_error_key_is_stable_after_json_round_trip()
	_test_completion_reason_is_authoritative()
	_test_malformed_state_is_not_advanced()
	_test_sequence_gaps_are_ignored_copies()

func _test_initial_schema_is_exact_and_isolated() -> void:
	var state := ProgressReducer.initial_state(PROFILE_ID)
	var keys := state.keys()
	keys.sort()
	assert_eq(
		keys,
		[
			"activity_progress",
			"apples",
			"collections",
			"coupons",
			"inventory",
			"last_sequence",
			"pending_review",
			"profile_id",
			"run_totals",
			"schema_version",
		]
	)
	assert_eq(state.schema_version, 1)
	assert_eq(state.profile_id, PROFILE_ID)
	assert_eq(state.last_sequence, 0)
	assert_eq(state.apples, 0)
	assert_eq(state.inventory, {})
	assert_eq(state.collections, [])
	assert_eq(state.coupons, [])
	assert_eq(state.pending_review, 0)
	assert_eq(state.activity_progress, {})
	assert_eq(state.run_totals, {"completed": 0, "health_depleted": 0})

	var second := ProgressReducer.initial_state(PROFILE_ID)
	state.inventory["stars"] = 9
	assert_eq(second.inventory, {}, "initial states must not share nested containers")

func _test_answers_and_health_depletion_preserve_rewards() -> void:
	var state := ProgressReducer.initial_state(PROFILE_ID)
	state = ProgressReducer.apply(state, _answer_event(1, true, 2, 11))
	state = ProgressReducer.apply(state, _answer_event(2, true, 2, 12))
	state = ProgressReducer.apply(state, _answer_event(3, false, 0, 13))
	state = ProgressReducer.apply(state, _run_completed_event(4, "health_depleted", 0, 4))

	assert_eq(state.apples, 4, "run completion must not double-count or clear earned rewards")
	assert_eq(state.activity_progress[ACTIVITY_ID].attempts, 3)
	assert_eq(state.activity_progress[ACTIVITY_ID].correct, 2)
	assert_eq(state.pending_review, 1)
	assert_eq(state.activity_progress[ACTIVITY_ID].repeated_errors.size(), 1)
	assert_eq(state.activity_progress[ACTIVITY_ID].repeated_errors.values()[0], 1)
	assert_eq(state.run_totals.completed, 0)
	assert_eq(state.run_totals.health_depleted, 1)
	assert_eq(state.last_sequence, 4)

	var repeated := ProgressReducer.initial_state(PROFILE_ID)
	repeated = ProgressReducer.apply(repeated, _answer_event(1, false, 0, 21))
	repeated = ProgressReducer.apply(repeated, _answer_event(2, false, 0, 22))
	assert_eq(repeated.activity_progress[ACTIVITY_ID].repeated_errors.size(), 1)
	assert_eq(repeated.activity_progress[ACTIVITY_ID].repeated_errors.values()[0], 2)

func _test_completion_inventory_collections_and_coupons() -> void:
	var state := ProgressReducer.initial_state(PROFILE_ID)
	var rewarded := _answer_event(1, true, 1, 31)
	rewarded.reward_delta = {"apples": 1, "stars": 3}
	state = ProgressReducer.apply(state, rewarded)
	state = ProgressReducer.apply(state, _run_completed_event(2, "target_reached", 2, 1))
	state = ProgressReducer.apply(state, _collection_event(3, "island_garden"))
	state = ProgressReducer.apply(state, _collection_event(4, "island_garden"))
	state = ProgressReducer.apply(state, _coupon_event(5, "guardian_bonus_1"))
	state = ProgressReducer.apply(state, _coupon_event(6, "guardian_bonus_1"))

	assert_eq(state.apples, 1)
	assert_eq(state.inventory, {"stars": 3})
	assert_eq(state.collections, ["island_garden"])
	assert_eq(state.coupons, ["guardian_bonus_1"])
	assert_eq(state.run_totals, {"completed": 1, "health_depleted": 0})
	assert_eq(state.last_sequence, 6)

func _test_duplicate_older_wrong_profile_and_invalid_events_are_ignored_copies() -> void:
	var state := ProgressReducer.apply(
		ProgressReducer.initial_state(PROFILE_ID), _answer_event(1, true, 2, 41)
	)
	state = ProgressReducer.apply(state, _answer_event(2, true, 2, 42))
	var duplicate := ProgressReducer.apply(state, _answer_event(2, true, 2, 43))
	assert_eq(duplicate, state)
	duplicate.activity_progress[ACTIVITY_ID].attempts = 99
	assert_eq(state.activity_progress[ACTIVITY_ID].attempts, 2, "duplicate result must be a deep copy")

	var older := ProgressReducer.apply(state, _answer_event(1, true, 2, 44))
	assert_eq(older, state)
	older.inventory["stars"] = 5
	assert_false(state.inventory.has("stars"), "older result must be a deep copy")

	var foreign := _answer_event(3, true, 2, 45)
	foreign.profile_id = "profile-b"
	assert_true(LearningEventV1.validate(foreign).is_empty())
	assert_eq(ProgressReducer.apply(state, foreign), state)

	var invalid := _answer_event(3, true, 2, 46)
	invalid.reward_delta = {"apples": -1}
	assert_false(LearningEventV1.validate(invalid).is_empty())
	assert_eq(ProgressReducer.apply(state, invalid), state)

func _test_safe_integer_overflow_does_not_advance() -> void:
	var state := ProgressReducer.initial_state(PROFILE_ID)
	state.run_totals.health_depleted = MAX_SAFE_INTEGER
	var result := ProgressReducer.apply(state, _run_completed_event(1, "health_depleted", 0, 0))
	assert_eq(result, state)
	result.run_totals.health_depleted = 0
	assert_eq(state.run_totals.health_depleted, MAX_SAFE_INTEGER, "overflow result must be a deep copy")

func _test_repeated_error_key_is_stable_after_json_round_trip() -> void:
	var live_event := _answer_event(1, false, 0, 51)
	var replayed_event: Dictionary = JSON.parse_string(JSON.stringify(live_event))
	var live_state := ProgressReducer.apply(ProgressReducer.initial_state(PROFILE_ID), live_event)
	var replayed_state := ProgressReducer.apply(
		ProgressReducer.initial_state(PROFILE_ID), replayed_event
	)
	assert_eq(
		replayed_state.activity_progress[ACTIVITY_ID].repeated_errors,
		live_state.activity_progress[ACTIVITY_ID].repeated_errors,
		"replay must derive the same repeated-error key as the live event",
	)

func _test_completion_reason_is_authoritative() -> void:
	var completed_at_zero := _run_completed_event(1, "target_reached", 0, 0)
	var state := ProgressReducer.apply(
		ProgressReducer.initial_state(PROFILE_ID), completed_at_zero
	)
	assert_eq(state.run_totals, {"completed": 1, "health_depleted": 0})

func _test_malformed_state_is_not_advanced() -> void:
	var missing_schema := ProgressReducer.initial_state(PROFILE_ID)
	missing_schema.erase("schema_version")
	var missing_schema_result := ProgressReducer.apply(
		missing_schema, _answer_event(1, true, 2, 61)
	)
	assert_eq(missing_schema_result, missing_schema)
	missing_schema_result.inventory["stars"] = 1
	assert_false(missing_schema.inventory.has("stars"), "invalid-state result must be a deep copy")

	var malformed_nested := ProgressReducer.initial_state(PROFILE_ID)
	malformed_nested.run_totals = {}
	malformed_nested.activity_progress[ACTIVITY_ID] = {"attempts": 0}
	assert_eq(
		ProgressReducer.apply(malformed_nested, _collection_event(1, "island_garden")),
		malformed_nested,
	)

func _test_sequence_gaps_are_ignored_copies() -> void:
	var initial := ProgressReducer.initial_state(PROFILE_ID)
	var initial_gap := ProgressReducer.apply(initial, _answer_event(2, true, 2, 71))
	assert_eq(initial_gap, initial, "an initial sequence gap must not advance progress")
	initial_gap.inventory["stars"] = 1
	assert_false(initial.inventory.has("stars"), "initial-gap result must be a deep copy")

	var midstream := ProgressReducer.apply(initial, _answer_event(1, true, 2, 72))
	var midstream_gap := ProgressReducer.apply(midstream, _answer_event(3, true, 2, 73))
	assert_eq(midstream_gap, midstream, "a midstream sequence gap must not advance progress")
	midstream_gap.activity_progress[ACTIVITY_ID].attempts = 99
	assert_eq(midstream.activity_progress[ACTIVITY_ID].attempts, 1, "midstream-gap result must be a deep copy")

func _answer_event(sequence: int, correctness: bool, apples: int, seed: int) -> Dictionary:
	return LearningEventV1.create(
		{"profile_id": PROFILE_ID, "device_id": DEVICE_ID, "sequence": sequence},
		{
			"session_id": "session-a",
			"client_timestamp": "2026-07-21T09:00:00Z",
			"event_type": "answer_submitted",
			"activity_id": ACTIVITY_ID,
			"content_version": "a-vertical-1",
			"question_seed": seed,
			"generator_id": "foundation_ten_rods",
			"band_id": "count_to_10",
			"resolved_parameters": {"left": 3, "right": 4},
			"submitted_answer": 7 if correctness else 8,
			"correct_answer": 7,
			"correctness": correctness,
			"response_duration_ms": 1200,
			"hints": 0,
			"health_delta": 0 if correctness else -1,
			"combo": 1 if correctness else 0,
			"reward_delta": {"apples": apples},
		}
	)

func _run_completed_event(sequence: int, reason: String, final_health: int, apples: int) -> Dictionary:
	return LearningEventV1.create(
		{"profile_id": PROFILE_ID, "device_id": DEVICE_ID, "sequence": sequence},
		{
			"session_id": "session-a",
			"client_timestamp": "2026-07-21T09:01:00Z",
			"event_type": "run_completed",
			"completion_reason": reason,
			"final_score": 2,
			"final_health": final_health,
			"earned_rewards": {"apples": apples},
		}
	)

func _collection_event(sequence: int, collection_id: String) -> Dictionary:
	return LearningEventV1.create(
		{"profile_id": PROFILE_ID, "device_id": DEVICE_ID, "sequence": sequence},
		{
			"client_timestamp": "2026-07-21T09:01:00Z",
			"event_type": "collection_unlocked",
			"collection_id": collection_id,
		}
	)

func _coupon_event(sequence: int, coupon_id: String) -> Dictionary:
	return LearningEventV1.create(
		{"profile_id": PROFILE_ID, "device_id": DEVICE_ID, "sequence": sequence},
		{
			"client_timestamp": "2026-07-21T09:01:00Z",
			"event_type": "coupon_earned",
			"coupon_id": coupon_id,
		}
	)
