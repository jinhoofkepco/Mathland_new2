class_name AdaptiveBandSelector
extends RefCounted

func select(
	activity: Dictionary,
	fixed_band_id: StringName,
	recent_events: Array,
	enabled: bool
) -> StringName:
	if not enabled or not activity.has("adaptive_policy"):
		return fixed_band_id
	var policy: Variant = activity.get("adaptive_policy")
	var bands: Variant = activity.get("difficulty_bands")
	if not policy is Dictionary or not bands is Array:
		return fixed_band_id
	var band_ids: Array[String] = []
	for band_value in bands:
		if not band_value is Dictionary or not band_value.get("band_id") is String:
			return fixed_band_id
		band_ids.append(band_value["band_id"])
	var current_index := band_ids.find(String(fixed_band_id))
	var minimum_index := band_ids.find(String(policy.get("min_band_id", "")))
	var maximum_index := band_ids.find(String(policy.get("max_band_id", "")))
	var window_size_value: Variant = policy.get("window_size")
	if (
		current_index < 0
		or minimum_index < 0
		or maximum_index < minimum_index
		or typeof(window_size_value) != TYPE_INT
		or int(window_size_value) < 1
	):
		return fixed_band_id
	var window_size := int(window_size_value)
	var eligible: Array[Dictionary] = []
	var activity_id := String(activity.get("activity_id", ""))
	var content_version := String(activity.get("content_version", ""))
	for event_value in recent_events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if _is_eligible(event, activity_id, content_version):
			eligible.append(event.duplicate(true))
	eligible.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["sequence"]) < int(right["sequence"])
	)
	if eligible.size() < window_size:
		return fixed_band_id
	var window := eligible.slice(eligible.size() - window_size)
	var score := 0.0
	var seen_incorrect_seeds := {}
	for event_value in window:
		var event: Dictionary = event_value
		if event["correctness"]:
			score += 1.0
		if int(event["hints"]) > 0:
			score -= 1.25
		if not event["correctness"]:
			var question_seed := int(event["question_seed"])
			if seen_incorrect_seeds.has(question_seed):
				score -= 0.25
			seen_incorrect_seeds[question_seed] = true
	var adjusted_correctness := clampf(score / float(window_size), 0.0, 1.0)
	var clamped_current := clampi(current_index, minimum_index, maximum_index)
	var promote_threshold: Variant = policy.get("promote_correctness")
	var demote_threshold: Variant = policy.get("demote_correctness")
	if not promote_threshold is float and not promote_threshold is int:
		return fixed_band_id
	if not demote_threshold is float and not demote_threshold is int:
		return fixed_band_id
	if adjusted_correctness >= float(promote_threshold):
		return StringName(band_ids[mini(maximum_index, clamped_current + 1)])
	if adjusted_correctness <= float(demote_threshold):
		return StringName(band_ids[maxi(minimum_index, clamped_current - 1)])
	return StringName(band_ids[clamped_current])

func _is_eligible(event: Dictionary, activity_id: String, content_version: String) -> bool:
	return (
		event.get("event_type") == "answer_submitted"
		and event.get("activity_id") == activity_id
		and event.get("content_version") == content_version
		and typeof(event.get("sequence")) == TYPE_INT
		and typeof(event.get("question_seed")) == TYPE_INT
		and event.get("correctness") is bool
		and typeof(event.get("hints")) == TYPE_INT
		and int(event["hints"]) >= 0
	)
