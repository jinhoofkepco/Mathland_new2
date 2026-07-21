extends "res://tests/support/test_case.gd"

const FIXTURE_PATH := "res://tests/fixtures/contracts/learning_event_v1.json"
const SAFE_INTEGER_MAX := 9007199254740991
const LearningEventV1 = preload("res://src/events/learning_event_v1.gd")

func run(_tree: SceneTree) -> void:
	var fixture := _load_fixture()
	var fixture_errors := LearningEventV1.validate(fixture)
	assert_true(fixture_errors.is_empty(), "Fixture errors: %s" % fixture_errors)
	_test_common_contract(fixture)
	_test_answer_contract(fixture)
	_test_type_specific_contracts(fixture)
	_test_timestamp_and_integer_boundaries(fixture)
	_test_create_preserves_reserved_context()

func _test_common_contract(fixture: Dictionary) -> void:
	var unknown := fixture.duplicate(true)
	unknown.injected = true
	assert_false(LearningEventV1.validate(unknown).is_empty())
	var invalid_type := fixture.duplicate(true)
	invalid_type.event_type = "invented"
	assert_false(LearningEventV1.validate(invalid_type).is_empty())
	var invalid_uuid := fixture.duplicate(true)
	invalid_uuid.event_id = "not-a-uuid"
	assert_false(LearningEventV1.validate(invalid_uuid).is_empty())
	for key in ["profile_id", "device_id"]:
		var invalid_context := fixture.duplicate(true)
		invalid_context[key] = ""
		assert_false(LearningEventV1.validate(invalid_context).is_empty())

func _test_answer_contract(fixture: Dictionary) -> void:
	var missing_answer := fixture.duplicate(true)
	missing_answer.erase("submitted_answer")
	assert_false(LearningEventV1.validate(missing_answer).is_empty())
	var missing_session := fixture.duplicate(true)
	missing_session.erase("session_id")
	assert_false(LearningEventV1.validate(missing_session).is_empty())
	var structured := fixture.duplicate(true)
	structured.submitted_answer = {"kind": "integer_list", "values": [2, 4], "order_matters": false}
	structured.correct_answer = {"kind": "integer", "value": 6}
	var structured_errors := LearningEventV1.validate(structured)
	assert_true(structured_errors.is_empty(), "Structured answer errors: %s" % structured_errors)
	var invented_answer_key := structured.duplicate(true)
	invented_answer_key.submitted_answer.extra = true
	assert_false(LearningEventV1.validate(invented_answer_key).is_empty())
	for key in ["response_duration_ms", "hints", "combo"]:
		var negative := fixture.duplicate(true)
		negative[key] = -1
		assert_false(LearningEventV1.validate(negative).is_empty())
	var invalid_reward := fixture.duplicate(true)
	invalid_reward.reward_delta = {"apples": -1}
	assert_false(LearningEventV1.validate(invalid_reward).is_empty())

func _test_type_specific_contracts(fixture: Dictionary) -> void:
	var run_started := _common_event(fixture, "run_started", true)
	run_started["activity_id"] = "foundation_ten_rods"
	run_started["content_version"] = "a-vertical-1"
	var run_started_errors := LearningEventV1.validate(run_started)
	assert_true(run_started_errors.is_empty(), "Run started errors: %s" % run_started_errors)
	var incomplete_start := run_started.duplicate(true)
	incomplete_start.erase("activity_id")
	assert_false(LearningEventV1.validate(incomplete_start).is_empty())

	var run_completed := _common_event(fixture, "run_completed", true)
	run_completed["completion_reason"] = "target_reached"
	run_completed["final_score"] = 8
	run_completed["final_health"] = 2
	run_completed["earned_rewards"] = {"apples": 4}
	var run_completed_errors := LearningEventV1.validate(run_completed)
	assert_true(run_completed_errors.is_empty(), "Run completed errors: %s" % run_completed_errors)
	var invalid_completion := run_completed.duplicate(true)
	invalid_completion.final_score = -1
	assert_false(LearningEventV1.validate(invalid_completion).is_empty())

	var collection := _common_event(fixture, "collection_unlocked", false)
	collection["collection_id"] = "island_garden"
	var collection_errors := LearningEventV1.validate(collection)
	assert_true(collection_errors.is_empty(), "Collection errors: %s" % collection_errors)
	var coupon := _common_event(fixture, "coupon_earned", false)
	coupon["coupon_id"] = "guardian_bonus_1"
	var coupon_errors := LearningEventV1.validate(coupon)
	assert_true(coupon_errors.is_empty(), "Coupon errors: %s" % coupon_errors)
	var foreign_field := collection.duplicate(true)
	foreign_field["coupon_id"] = "wrong_type_field"
	assert_false(LearningEventV1.validate(foreign_field).is_empty())

func _test_timestamp_and_integer_boundaries(fixture: Dictionary) -> void:
	var leap_day := fixture.duplicate(true)
	leap_day.client_timestamp = "2024-02-29T23:59:59Z"
	var leap_day_errors := LearningEventV1.validate(leap_day)
	assert_true(leap_day_errors.is_empty(), "Leap day errors: %s" % leap_day_errors)
	for timestamp in ["2026-02-29T09:00:00Z", "2026-07-21T24:00:00Z", "2026-07-21T09:00:00+00:00", "xxxxxxxxxxxxxxxxxxxZ"]:
		var invalid_timestamp := fixture.duplicate(true)
		invalid_timestamp.client_timestamp = timestamp
		assert_false(LearningEventV1.validate(invalid_timestamp).is_empty())
	for key in ["sequence", "question_seed", "response_duration_ms", "hints", "health_delta", "combo"]:
		var unsafe := fixture.duplicate(true)
		unsafe[key] = float(SAFE_INTEGER_MAX) + 1024.0
		assert_false(LearningEventV1.validate(unsafe).is_empty())
	var zero_sequence := fixture.duplicate(true)
	zero_sequence.sequence = 0
	assert_false(LearningEventV1.validate(zero_sequence).is_empty())

func _test_create_preserves_reserved_context() -> void:
	var created := LearningEventV1.create(
		{"profile_id": "profile-a", "device_id": "device-a", "sequence": 7},
		{
			"profile_id": "profile-b",
			"device_id": "device-b",
			"sequence": 99,
			"client_timestamp": "2026-07-21T09:00:00Z",
			"event_type": "coupon_earned",
			"coupon_id": "welcome",
		}
	)
	assert_eq(created.profile_id, "profile-a")
	assert_eq(created.device_id, "device-a")
	assert_eq(created.sequence, 7)

func _common_event(fixture: Dictionary, event_type: String, include_session: bool) -> Dictionary:
	var event := {}
	for key in ["contract_version", "event_id", "profile_id", "device_id", "sequence", "client_timestamp"]:
		event[key] = fixture[key]
	event["event_type"] = event_type
	if include_session:
		event["session_id"] = fixture.session_id
	return event

func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed
