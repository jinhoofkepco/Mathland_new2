class_name DailyObjectiveService
extends RefCounted

const OBJECTIVES: Array[Dictionary] = [
	{
		"objective_id": "complete_three",
		"label_key": "objective.complete_three",
		"activity_id": "foundation_ten_rods",
		"target": 3,
	},
	{
		"objective_id": "correct_five",
		"label_key": "objective.correct_five",
		"activity_id": "foundation_ten_rods",
		"target": 5,
	},
	{
		"objective_id": "protect_hearts",
		"label_key": "objective.protect_hearts",
		"activity_id": "foundation_ten_rods",
		"target": 1,
	},
	{
		"objective_id": "practice_foundations",
		"label_key": "objective.practice_foundations",
		"activity_id": "foundation_ten_rods",
		"target": 1,
	},
	{
		"objective_id": "review_two",
		"label_key": "objective.review_two",
		"activity_id": "foundation_ten_rods",
		"target": 2,
	},
	{
		"objective_id": "earn_ten_apples",
		"label_key": "objective.earn_ten_apples",
		"activity_id": "foundation_ten_rods",
		"target": 10,
	},
]

func objectives(profile_id: String, yyyy_mm_dd: String) -> Array[Dictionary]:
	if profile_id.strip_edges().is_empty() or not _is_iso_date(yyyy_mm_dd):
		return []
	var seed := "%s|%s" % [profile_id, yyyy_mm_dd]
	var ranked: Array[Dictionary] = []
	for objective in OBJECTIVES:
		var candidate: Dictionary = objective.duplicate(true)
		candidate["_rank"] = "%s|%s" % [seed, candidate.objective_id]
		candidate._rank = candidate._rank.sha256_text()
		ranked.append(candidate)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary):
		if left._rank == right._rank:
			return left.objective_id < right.objective_id
		return left._rank < right._rank
	)
	var selected: Array[Dictionary] = []
	for index in 3:
		var objective: Dictionary = ranked[index].duplicate(true)
		objective.erase("_rank")
		selected.append(objective)
	return selected

func objective_ids() -> Array[String]:
	var ids: Array[String] = []
	for objective in OBJECTIVES:
		ids.append(objective.objective_id)
	return ids

func _is_iso_date(value: String) -> bool:
	if value.length() != 10 or value[4] != "-" or value[7] != "-":
		return false
	var year := value.substr(0, 4)
	var month := value.substr(5, 2)
	var day := value.substr(8, 2)
	if not year.is_valid_int() or not month.is_valid_int() or not day.is_valid_int():
		return false
	var month_number := month.to_int()
	var day_number := day.to_int()
	return month_number >= 1 and month_number <= 12 and day_number >= 1 and day_number <= 31
