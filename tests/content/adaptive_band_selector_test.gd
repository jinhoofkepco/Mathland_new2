extends "res://tests/support/test_case.gd"

const AdaptiveBandSelectorScript = preload("res://src/content/adaptive_band_selector.gd")

func run(_tree: SceneTree) -> void:
	var selector := AdaptiveBandSelectorScript.new()
	assert_eq(selector.select(_activity(), &"practice", [], false), &"practice")
	assert_eq(selector.select(_activity(false), &"practice", [], true), &"practice")
	assert_eq(selector.select(_activity(), &"practice", [_answer(1, true)], true), &"practice")
	assert_eq(
		selector.select(
			_activity(), &"intro",
			[_answer(1, true), _answer(2, true), _answer(3, true), _answer(4, false)], true
		),
		&"practice"
	)
	assert_eq(
		selector.select(
			_activity(), &"challenge",
			[_answer(1, false), _answer(2, true), _answer(3, false), _answer(4, false)], true
		),
		&"practice"
	)
	_test_window_filters_penalties_bounds_and_immutability(selector)
	_test_unsafe_event_integers_are_ignored(selector)

func _test_window_filters_penalties_bounds_and_immutability(selector: Variant) -> void:
	var activity := _activity()
	var history := [
		_answer(1, false), _answer(2, false), _answer(3, false), _answer(4, false),
		_answer(5, true, 1), _answer(6, true), _answer(7, true), _answer(8, true),
	]
	var activity_snapshot: Dictionary = activity.duplicate(true)
	var history_snapshot: Array = history.duplicate(true)
	assert_eq(selector.select(activity, &"practice", history, true), &"practice")
	assert_eq(activity, activity_snapshot)
	assert_eq(history, history_snapshot)
	var bounded := _activity()
	bounded["adaptive_policy"]["min_band_id"] = "practice"
	assert_eq(
		selector.select(
			bounded, &"practice",
			[_answer(1, false), _answer(2, false), _answer(3, false), _answer(4, false)], true
		),
		&"practice"
	)

func _test_unsafe_event_integers_are_ignored(selector: Variant) -> void:
	var invalid_events := [
		_answer(0, true),
		_answer(9007199254740992, true),
		_answer(2, true, 0, 0x100000000),
		_answer(3, true, 9007199254740992),
	]
	var valid_but_incomplete := [_answer(10, true), _answer(11, true), _answer(12, true)]
	for invalid_event in invalid_events:
		assert_eq(
			selector.select(_activity(), &"intro", [invalid_event] + valid_but_incomplete, true),
			&"intro"
		)

func _activity(with_policy: bool = true) -> Dictionary:
	var activity := {
		"activity_id": "addition_ones",
		"content_version": "1.2.3",
		"difficulty_bands": [
			{"band_id": "intro"}, {"band_id": "practice"}, {"band_id": "challenge"},
		],
		"run": {"starting_hearts": 3},
	}
	if with_policy:
		activity["adaptive_policy"] = {
			"enabled_by_default": false,
			"min_band_id": "intro",
			"max_band_id": "challenge",
			"window_size": 4,
			"promote_correctness": 0.75,
			"demote_correctness": 0.35,
		}
	return activity

func _answer(sequence: int, correctness: bool, hints: int = 0, question_seed: int = -1) -> Dictionary:
	return {
		"event_type": "answer_submitted",
		"activity_id": "addition_ones",
		"content_version": "1.2.3",
		"sequence": sequence,
		"question_seed": sequence if question_seed < 0 else question_seed,
		"correctness": correctness,
		"hints": hints,
	}
