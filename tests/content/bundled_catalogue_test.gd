extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")
const QuestionEngineScript = preload("res://src/content/question_engine.gd")
const IDS := [
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

func run(_tree: SceneTree) -> void:
	var repository: Variant = ContentRepositoryScript.new()
	var initialized: Variant = repository.initialize(
		"res://content/active-manifest.json",
		"user://tests/no-bundled-catalogue-cache"
	)
	assert_true(initialized.ok, str(initialized.issues))
	if not initialized.ok:
		return
	assert_eq(repository.get_manifest_version(), "1.0.0")
	assert_eq(repository.list_activities().size(), IDS.size())

	var band_count := 0
	var sample_count := 0
	for activity_id in IDS:
		assert_eq(repository.get_active_version(StringName(activity_id)), "1.0.0")
		var activity: Dictionary = repository.get_activity(StringName(activity_id))
		assert_false(activity.is_empty(), activity_id)
		if activity.is_empty():
			continue
		band_count += activity.difficulty_bands.size()
		var engine: Variant = QuestionEngineScript.new()
		for sample_value in activity.validation_samples:
			var sample: Dictionary = sample_value
			var question: Dictionary = engine.generate_question(
				activity,
				StringName(sample.band_id),
				int(sample.seed)
			)
			assert_false(question.is_empty(), "%s/%s/%s:%s" % [
				activity_id,
				sample.band_id,
				sample.seed,
				engine.last_diagnostic,
			])
			if question.is_empty():
				continue
			assert_eq(question.correct_answer, sample.expected_answer)
			sample_count += 1
	assert_eq(band_count, 33)
	assert_eq(sample_count, 132)
