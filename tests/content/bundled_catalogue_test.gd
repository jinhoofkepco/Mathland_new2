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
const PROMPT_CATALOGUES := {
	"ko": "res://resources/i18n/ko.po",
	"en": "res://resources/i18n/en.po",
}

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
	var prompt_keys := {}
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
			var prompt: Variant = question.get("prompt", {})
			if prompt is Dictionary:
				var prompt_key := String(prompt.get("key", ""))
				if not prompt_key.is_empty():
					prompt_keys[prompt_key] = true
			sample_count += 1
	assert_eq(band_count, 33)
	assert_eq(sample_count, 132)
	assert_eq(prompt_keys.size(), IDS.size())

	var previous_locale := TranslationServer.get_locale()
	for locale in PROMPT_CATALOGUES:
		var catalogue := _read_single_line_po(PROMPT_CATALOGUES[locale])
		TranslationServer.set_locale(locale)
		for prompt_key in prompt_keys:
			assert_true(
				catalogue.has(prompt_key),
				"%s catalogue is missing prompt key %s" % [locale, prompt_key]
			)
			assert_false(
				String(catalogue.get(prompt_key, "")).is_empty(),
				"%s catalogue has an empty prompt for %s" % [locale, prompt_key]
			)
			assert_ne(
				TranslationServer.translate(prompt_key),
				prompt_key,
				"%s exposed raw prompt key %s" % [locale, prompt_key]
			)
	assert_eq(
		_read_single_line_po(PROMPT_CATALOGUES.ko).get(
			"question.prime_factorization",
			""
		),
		"{value}의 소인수를 찾아보세요."
	)
	TranslationServer.set_locale(previous_locale)


func _read_single_line_po(path: String) -> Dictionary:
	var entries := {}
	var current_id := ""
	for line_value in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(line_value)
		if line.begins_with("msgid "):
			current_id = _parse_po_string(line.trim_prefix("msgid "))
		elif not current_id.is_empty() and line.begins_with("msgstr "):
			entries[current_id] = _parse_po_string(line.trim_prefix("msgstr "))
			current_id = ""
	return entries


func _parse_po_string(value: String) -> String:
	var parsed: Variant = JSON.parse_string(value)
	return String(parsed) if parsed is String else ""
