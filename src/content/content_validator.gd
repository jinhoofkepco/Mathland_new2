class_name ContentValidator
extends RefCounted

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const ValidationResult = preload("res://src/content/content_validation_result.gd")

var _number_pattern := RegEx.create_from_string("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
var _safe_tuning_key_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$")
var _timestamp_pattern := RegEx.create_from_string(
	"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
)

func parse_json(source: String, source_name: String = "") -> ContentValidationResult:
	var issues: Array[Dictionary] = []
	if _utf16_length(source) > Contract.MAX_JSON_SOURCE_LENGTH:
		_add_issue(issues, "SOURCE_TOO_LARGE", [], "JSON source exceeds the content limit")
		return ValidationResult.new(false, issues, null, source_name)

	var state := {"source": source, "index": 0, "issues": issues}
	_skip_whitespace(state)
	if not _scan_value(state, [], 0):
		return ValidationResult.new(false, issues, null, source_name)
	_skip_whitespace(state)
	if int(state["index"]) != source.length():
		_add_issue(issues, "INVALID_JSON", [], "Unexpected trailing JSON input")
		return ValidationResult.new(false, issues, null, source_name)

	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK:
		_add_issue(
			issues,
			"INVALID_JSON",
			[],
			"Malformed JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
		return ValidationResult.new(false, issues, null, source_name)
	var parsed: Variant = _normalize_json_numbers(parser.data)
	_validate_json_domain(parsed, [], issues)
	return ValidationResult.new(issues.is_empty(), issues, parsed, source_name)

func validate_package(package: Dictionary) -> ContentValidationResult:
	var issues: Array[Dictionary] = []
	_validate_package_shape(package, issues)
	if issues.is_empty():
		var canonical := canonical_json(package, true)
		if canonical.is_empty():
			_add_issue(issues, "CANONICAL_JSON", [], "Package cannot be represented as canonical JSON")
		else:
			var expected := _sha256(canonical)
			if String(package.get("checksum", "")) != expected:
				_add_issue(issues, "CHECKSUM_MISMATCH", ["checksum"], "Package checksum does not match authored fields")
	return ValidationResult.new(issues.is_empty(), issues, package)

func validate_manifest(manifest: Dictionary, packages_by_path: Dictionary) -> ContentValidationResult:
	var issues: Array[Dictionary] = []
	_validate_manifest_shape(manifest, issues)
	if packages_by_path.size() != Contract.ACTIVITY_IDS.size():
		_add_issue(issues, "PACKAGE_SET_SIZE", ["packages"], "Manifest candidate must contain the full catalogue")

	var entries_value: Variant = manifest.get("packages")
	if entries_value is Array:
		var entries: Array = entries_value
		for index in entries.size():
			var entry_value: Variant = entries[index]
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			var path := String(entry.get("path", ""))
			if not packages_by_path.has(path):
				_add_issue(issues, "MANIFEST_PACKAGE_MISSING", ["packages", index], "Manifest package is missing")
				continue
			var package_value: Variant = packages_by_path[path]
			if not package_value is Dictionary:
				_add_issue(issues, "MANIFEST_PACKAGE_TYPE", ["packages", index], "Manifest package must be an object")
				continue
			var package: Dictionary = package_value
			var package_result := validate_package(package)
			for package_issue in package_result.issues:
				var nested_issue: Dictionary = package_issue.duplicate(true)
				var nested_path: Array = ["packages", index, "package"]
				nested_path.append_array(nested_issue.get("path", []))
				nested_issue["path"] = nested_path
				issues.append(nested_issue)
			if (
				package.get("activity_id") != entry.get("activity_id")
				or package.get("content_version") != entry.get("content_version")
			):
				_add_issue(issues, "MANIFEST_PACKAGE_IDENTITY", ["packages", index], "Package identity differs from manifest entry")
			if package.get("checksum") != entry.get("checksum"):
				_add_issue(issues, "MANIFEST_CHECKSUM_MISMATCH", ["packages", index, "checksum"], "Package checksum differs from manifest entry")
	return ValidationResult.new(issues.is_empty(), issues, manifest)

func validate_manifest_structure(manifest: Dictionary) -> ContentValidationResult:
	var issues: Array[Dictionary] = []
	_validate_manifest_shape(manifest, issues)
	return ValidationResult.new(issues.is_empty(), issues, manifest)

func canonical_json(value: Variant, omit_top_level_checksum: bool = false) -> String:
	var state := {"ok": true}
	var encoded := _encode_canonical(value, 0, omit_top_level_checksum, state)
	return encoded if bool(state["ok"]) else ""

func content_checksum(package: Dictionary) -> String:
	var canonical := canonical_json(package, true)
	return _sha256(canonical) if not canonical.is_empty() else ""

func _validate_package_shape(package: Dictionary, issues: Array[Dictionary]) -> void:
	_expect_exact_keys(package, Contract.REQUIRED_PACKAGE_KEYS, Contract.OPTIONAL_PACKAGE_KEYS, [], issues)
	_validate_json_domain(package, [], issues)
	if package.get("schema_version") != Contract.SCHEMA_VERSION:
		_add_issue(issues, "UNSUPPORTED_SCHEMA", ["schema_version"], "Only content schema version 1 is supported")
	if not _is_semantic_version(package.get("content_version")):
		_add_issue(issues, "SEMANTIC_VERSION", ["content_version"], "Expected a semantic content version")

	var activity_id := String(package.get("activity_id", ""))
	if activity_id not in Contract.ACTIVITY_IDS:
		_add_issue(issues, "UNKNOWN_ACTIVITY_ID", ["activity_id"], "Activity ID is not allowlisted")
	var icon_id := String(package.get("icon_id", ""))
	if icon_id not in Contract.ICON_IDS:
		_add_issue(issues, "UNKNOWN_ICON_ID", ["icon_id"], "Icon ID is not allowlisted")
	elif icon_id != activity_id:
		_add_issue(issues, "ICON_ACTIVITY_MISMATCH", ["icon_id"], "Activity packages use their activity icon")
	if String(package.get("scene_id", "")) not in Contract.SCENE_IDS:
		_add_issue(issues, "UNKNOWN_SCENE_ID", ["scene_id"], "Scene ID is not allowlisted")
	if not _is_checksum(package.get("checksum")):
		_add_issue(issues, "CHECKSUM_FORMAT", ["checksum"], "Expected a lowercase SHA-256 checksum")

	_validate_localizations(package.get("localizations"), issues)
	_validate_run(package.get("run"), issues)
	_validate_bands(package.get("difficulty_bands"), activity_id, issues)
	if package.has("adaptive_policy"):
		_validate_adaptive_policy(package["adaptive_policy"], issues)
	_validate_samples(package.get("validation_samples"), issues)

func _validate_localizations(value: Variant, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", ["localizations"], "Localizations must be an object")
		return
	var localizations: Dictionary = value
	_expect_exact_keys(localizations, Contract.LOCALIZATION_ROOT_KEYS, [], ["localizations"], issues)
	var korean_value: Variant = localizations.get("ko-KR")
	if not korean_value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", ["localizations", "ko-KR"], "Korean localization must be an object")
		return
	var korean: Dictionary = korean_value
	_expect_exact_keys(korean, Contract.LOCALIZATION_KEYS, [], ["localizations", "ko-KR"], issues)
	_validate_trimmed_text(korean.get("title"), Contract.MAX_TITLE_CODEPOINTS, ["localizations", "ko-KR", "title"], issues)
	_validate_trimmed_text(korean.get("description"), Contract.MAX_DESCRIPTION_CODEPOINTS, ["localizations", "ko-KR", "description"], issues)
	var steps_value: Variant = korean.get("tutorial_steps")
	if not steps_value is Array:
		_add_issue(issues, "SCHEMA_TYPE", ["localizations", "ko-KR", "tutorial_steps"], "Tutorial steps must be an array")
		return
	var steps: Array = steps_value
	if steps.is_empty() or steps.size() > 12:
		_add_issue(issues, "SCHEMA_SIZE", ["localizations", "ko-KR", "tutorial_steps"], "Tutorial steps require 1 to 12 entries")
	for index in steps.size():
		_validate_trimmed_text(steps[index], Contract.MAX_TUTORIAL_CODEPOINTS, ["localizations", "ko-KR", "tutorial_steps", index], issues)

func _validate_run(value: Variant, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", ["run"], "Run tuning must be an object")
		return
	var run: Dictionary = value
	_expect_exact_keys(run, Contract.RUN_KEYS, [], ["run"], issues)
	_validate_positive_integer(run.get("starting_hearts"), ["run", "starting_hearts"], issues)
	_validate_positive_integer(run.get("boss_every_correct"), ["run", "boss_every_correct"], issues)

	var goal_value: Variant = run.get("goal")
	if goal_value is Dictionary:
		var goal: Dictionary = goal_value
		_expect_exact_keys(goal, Contract.GOAL_KEYS, [], ["run", "goal"], issues)
		if goal.get("kind") != "correct_answers":
			_add_issue(issues, "SCHEMA_LITERAL", ["run", "goal", "kind"], "Only correct-answer goals are supported")
		_validate_positive_integer(goal.get("target"), ["run", "goal", "target"], issues)
	else:
		_add_issue(issues, "SCHEMA_TYPE", ["run", "goal"], "Goal must be an object")

	var timer_value: Variant = run.get("timer")
	if timer_value is Dictionary:
		var timer: Dictionary = timer_value
		_expect_exact_keys(timer, Contract.TIMER_KEYS, [], ["run", "timer"], issues)
		_validate_boolean(timer.get("enabled"), ["run", "timer", "enabled"], issues)
		_validate_positive_integer(timer.get("seconds"), ["run", "timer", "seconds"], issues)
		_validate_boolean(timer.get("profile_can_disable"), ["run", "timer", "profile_can_disable"], issues)
	else:
		_add_issue(issues, "SCHEMA_TYPE", ["run", "timer"], "Timer must be an object")

	var rewards_value: Variant = run.get("rewards")
	if rewards_value is Dictionary:
		var rewards: Dictionary = rewards_value
		_expect_exact_keys(rewards, Contract.REWARDS_KEYS, [], ["run", "rewards"], issues)
		_validate_positive_integer(rewards.get("apples_per_correct"), ["run", "rewards", "apples_per_correct"], issues)
		_validate_positive_integer(rewards.get("completion_apples"), ["run", "rewards", "completion_apples"], issues)
	else:
		_add_issue(issues, "SCHEMA_TYPE", ["run", "rewards"], "Rewards must be an object")

	var thresholds_value: Variant = run.get("combo_thresholds")
	if thresholds_value is Array:
		var thresholds: Array = thresholds_value
		if thresholds.size() != 3:
			_add_issue(issues, "SCHEMA_SIZE", ["run", "combo_thresholds"], "Exactly three combo thresholds are required")
		for index in thresholds.size():
			_validate_positive_integer(thresholds[index], ["run", "combo_thresholds", index], issues)
		if (
			thresholds.size() == 3
			and _is_positive_integer(thresholds[0])
			and _is_positive_integer(thresholds[1])
			and _is_positive_integer(thresholds[2])
			and not (int(thresholds[0]) < int(thresholds[1]) and int(thresholds[1]) < int(thresholds[2]))
		):
			_add_issue(issues, "COMBO_THRESHOLDS", ["run", "combo_thresholds"], "Combo thresholds must increase strictly")
	else:
		_add_issue(issues, "SCHEMA_TYPE", ["run", "combo_thresholds"], "Combo thresholds must be an array")

	var effects_value: Variant = run.get("effects")
	if effects_value is Dictionary:
		var effects: Dictionary = effects_value
		_expect_exact_keys(effects, Contract.EFFECT_KEYS, [], ["run", "effects"], issues)
		for effect_key in Contract.EFFECT_KEYS:
			if String(effects.get(effect_key, "")) not in Contract.EFFECT_PRESET_IDS:
				_add_issue(issues, "UNKNOWN_EFFECT_ID", ["run", "effects", effect_key], "Effect preset is not allowlisted")
	else:
		_add_issue(issues, "SCHEMA_TYPE", ["run", "effects"], "Effects must be an object")

func _validate_bands(value: Variant, activity_id: String, issues: Array[Dictionary]) -> void:
	if not value is Array:
		_add_issue(issues, "SCHEMA_TYPE", ["difficulty_bands"], "Difficulty bands must be an array")
		return
	var bands: Array = value
	if bands.size() != Contract.BAND_IDS.size():
		_add_issue(issues, "SCHEMA_SIZE", ["difficulty_bands"], "Exactly three ordered difficulty bands are required")
	for index in bands.size():
		var band_value: Variant = bands[index]
		if not band_value is Dictionary:
			_add_issue(issues, "SCHEMA_TYPE", ["difficulty_bands", index], "Difficulty band must be an object")
			continue
		var band: Dictionary = band_value
		var path: Array = ["difficulty_bands", index]
		_expect_exact_keys(band, Contract.BAND_KEYS, [], path, issues)
		if index >= Contract.BAND_IDS.size() or band.get("band_id") != Contract.BAND_IDS[index]:
			_add_issue(issues, "BAND_ORDER", path + ["band_id"], "Difficulty bands must be intro, practice, challenge")
		var generator_id := String(band.get("generator_id", ""))
		if generator_id not in Contract.GENERATOR_IDS:
			_add_issue(issues, "UNKNOWN_GENERATOR_ID", path + ["generator_id"], "Generator is not allowlisted")
		elif Contract.ACTIVITY_GENERATOR_IDS.get(activity_id, "") != generator_id:
			_add_issue(issues, "GENERATOR_ACTIVITY_MISMATCH", path + ["generator_id"], "Generator does not belong to this activity")
		_validate_parameters(band.get("generator_parameters"), path + ["generator_parameters"], issues)
		_validate_answer_layout(band.get("answer_layout"), path + ["answer_layout"], issues)
		_validate_manipulative(band.get("manipulative"), path + ["manipulative"], issues)

func _validate_answer_layout(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", path, "Answer layout must be an object")
		return
	var layout: Dictionary = value
	_expect_exact_keys(layout, Contract.ANSWER_LAYOUT_REQUIRED_KEYS, Contract.ANSWER_LAYOUT_OPTIONAL_KEYS, path, issues)
	if String(layout.get("id", "")) not in Contract.ANSWER_LAYOUT_IDS:
		_add_issue(issues, "UNKNOWN_ANSWER_LAYOUT_ID", path + ["id"], "Answer layout is not allowlisted")
	if layout.has("options"):
		_validate_parameters(layout["options"], path + ["options"], issues)

func _validate_manipulative(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", path, "Manipulative config must be an object")
		return
	var config: Dictionary = value
	_expect_exact_keys(config, Contract.MANIPULATIVE_KEYS, [], path, issues)
	if String(config.get("id", "")) not in Contract.MANIPULATIVE_IDS:
		_add_issue(issues, "UNKNOWN_MANIPULATIVE_ID", path + ["id"], "Manipulative is not allowlisted")
	_validate_parameters(config.get("config"), path + ["config"], issues)
	_validate_parameters(config.get("initial_state"), path + ["initial_state"], issues)

func _validate_parameters(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", path, "Resolved parameters must be an object")
		return
	var parameters: Dictionary = value
	for key_value in parameters.keys():
		if not key_value is String:
			_add_issue(issues, "UNSAFE_TUNING_KEY", path, "Parameter keys must be strings")
			continue
		var key: String = key_value
		if key in Contract.FORBIDDEN_OBJECT_KEYS or _safe_tuning_key_pattern.search(key) == null:
			_add_issue(issues, "UNSAFE_TUNING_KEY", path + [key], "Parameter key is not a safe identifier")
		var parameter: Variant = parameters[key]
		if parameter is bool:
			continue
		if _is_safe_integer(parameter):
			continue
		if parameter is String:
			var string_value: String = parameter
			if string_value.length() > 128 or not _is_ecmascript_trimmed(string_value):
				_add_issue(issues, "SCHEMA_STRING", path + [key], "Parameter string is empty, padded, or too long")
			elif _safe_tuning_key_pattern.search(string_value) == null and string_value not in ["+", "-", "*", "/", "%"]:
				_add_issue(issues, "UNSAFE_TUNING_STRING", path + [key], "Parameter string cannot be a path, URL, or code")
			continue
		if parameter is Array:
			var integer_values: Array = parameter
			if integer_values.size() > 128:
				_add_issue(issues, "SCHEMA_SIZE", path + [key], "Parameter array is too long")
			for index in integer_values.size():
				if not _is_safe_integer(integer_values[index]):
					_add_issue(issues, "SCHEMA_TYPE", path + [key, index], "Parameter arrays contain only safe integers")
			continue
		_add_issue(issues, "SCHEMA_TYPE", path + [key], "Unsupported parameter value")

func _validate_adaptive_policy(value: Variant, issues: Array[Dictionary]) -> void:
	var path: Array = ["adaptive_policy"]
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", path, "Adaptive policy must be an object")
		return
	var policy: Dictionary = value
	_expect_exact_keys(policy, Contract.ADAPTIVE_POLICY_KEYS, [], path, issues)
	if policy.get("enabled_by_default") != false or not policy.get("enabled_by_default") is bool:
		_add_issue(issues, "ADAPTIVE_DEFAULT", path + ["enabled_by_default"], "Adaptive difficulty must default to off")
	_validate_positive_integer(policy.get("window_size"), path + ["window_size"], issues)
	var minimum := String(policy.get("min_band_id", ""))
	var maximum := String(policy.get("max_band_id", ""))
	_validate_trimmed_text(minimum, 32, path + ["min_band_id"], issues)
	_validate_trimmed_text(maximum, 32, path + ["max_band_id"], issues)
	var minimum_index := Contract.BAND_IDS.find(minimum)
	var maximum_index := Contract.BAND_IDS.find(maximum)
	if minimum_index < 0 or maximum_index < 0 or minimum_index > maximum_index:
		_add_issue(issues, "ADAPTIVE_BOUNDS", path, "Adaptive bounds must reference ordered bands")
	var promote_value: Variant = policy.get("promote_correctness")
	var demote_value: Variant = policy.get("demote_correctness")
	if not _is_probability(promote_value):
		_add_issue(issues, "SCHEMA_RANGE", path + ["promote_correctness"], "Promotion correctness must be from 0 to 1")
	if not _is_probability(demote_value):
		_add_issue(issues, "SCHEMA_RANGE", path + ["demote_correctness"], "Demotion correctness must be from 0 to 1")
	if _is_probability(promote_value) and _is_probability(demote_value) and float(demote_value) >= float(promote_value):
		_add_issue(issues, "ADAPTIVE_THRESHOLDS", path, "Demotion correctness must be below promotion correctness")

func _validate_samples(value: Variant, issues: Array[Dictionary]) -> void:
	var path: Array = ["validation_samples"]
	if not value is Array:
		_add_issue(issues, "SCHEMA_TYPE", path, "Validation samples must be an array")
		return
	var samples: Array = value
	var seen := {}
	for index in samples.size():
		var sample_value: Variant = samples[index]
		if not sample_value is Dictionary:
			_add_issue(issues, "SCHEMA_TYPE", path + [index], "Validation sample must be an object")
			continue
		var sample: Dictionary = sample_value
		_expect_exact_keys(sample, Contract.VALIDATION_SAMPLE_KEYS, [], path + [index], issues)
		var band_id := String(sample.get("band_id", ""))
		if band_id not in Contract.BAND_IDS:
			_add_issue(issues, "UNKNOWN_BAND_ID", path + [index, "band_id"], "Validation sample band is unknown")
		var seed_value: Variant = sample.get("seed")
		if not _is_nonnegative_integer(seed_value):
			_add_issue(issues, "SCHEMA_RANGE", path + [index, "seed"], "Validation seed must be a nonnegative safe integer")
		else:
			seen["%s:%d" % [band_id, int(seed_value)]] = true
		_validate_answer_value(sample.get("expected_answer"), path + [index, "expected_answer"], issues)
	var complete := samples.size() == Contract.BAND_IDS.size() * Contract.VALIDATION_SEEDS.size()
	for band_id in Contract.BAND_IDS:
		for seed in Contract.VALIDATION_SEEDS:
			complete = complete and seen.has("%s:%d" % [band_id, seed])
	if not complete or seen.size() != Contract.BAND_IDS.size() * Contract.VALIDATION_SEEDS.size():
		_add_issue(issues, "VALIDATION_SAMPLES", path, "Every band requires seeds 1, 7, 42, and 20260721 exactly once")

func _validate_answer_value(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not value is Dictionary:
		_add_issue(issues, "SCHEMA_TYPE", path, "Answer value must be an object")
		return
	var answer: Dictionary = value
	var kind := String(answer.get("kind", ""))
	if kind == "integer":
		_expect_exact_keys(answer, Contract.INTEGER_ANSWER_KEYS, [], path, issues)
		if not _is_safe_integer(answer.get("value")):
			_add_issue(issues, "SCHEMA_TYPE", path + ["value"], "Integer answer must be a safe integer")
	elif kind == "integer_list":
		_expect_exact_keys(answer, Contract.INTEGER_LIST_ANSWER_KEYS, [], path, issues)
		var values_value: Variant = answer.get("values")
		if values_value is Array:
			var values: Array = values_value
			if values.is_empty() or values.size() > 64:
				_add_issue(issues, "SCHEMA_SIZE", path + ["values"], "Integer-list answers require 1 to 64 values")
			for index in values.size():
				if not _is_safe_integer(values[index]):
					_add_issue(issues, "SCHEMA_TYPE", path + ["values", index], "Answer list contains only safe integers")
		else:
			_add_issue(issues, "SCHEMA_TYPE", path + ["values"], "Answer values must be an array")
		_validate_boolean(answer.get("order_matters"), path + ["order_matters"], issues)
	else:
		_add_issue(issues, "SCHEMA_UNION", path + ["kind"], "Unknown answer kind")

func _validate_manifest_shape(manifest: Dictionary, issues: Array[Dictionary]) -> void:
	_expect_exact_keys(manifest, Contract.REQUIRED_MANIFEST_KEYS, [], [], issues)
	_validate_json_domain(manifest, [], issues)
	if manifest.get("schema_version") != Contract.SCHEMA_VERSION:
		_add_issue(issues, "UNSUPPORTED_SCHEMA", ["schema_version"], "Only manifest schema version 1 is supported")
	if manifest.get("manifest_version") != Contract.MANIFEST_VERSION:
		_add_issue(issues, "MANIFEST_VERSION", ["manifest_version"], "Only manifest version 1.0.0 is supported")
	if not _is_iso_timestamp(manifest.get("published_at")):
		_add_issue(issues, "TIMESTAMP", ["published_at"], "Published timestamp must be a valid ISO timestamp with offset")

	var order_value: Variant = manifest.get("activity_order")
	if not order_value is Array:
		_add_issue(issues, "SCHEMA_TYPE", ["activity_order"], "Activity order must be an array")
	else:
		var order: Array = order_value
		if not _same_string_sequence(order, Contract.ACTIVITY_IDS):
			_add_issue(issues, "MANIFEST_ACTIVITY_ORDER", ["activity_order"], "Activity order must match the complete catalogue")

	var packages_value: Variant = manifest.get("packages")
	if not packages_value is Array:
		_add_issue(issues, "SCHEMA_TYPE", ["packages"], "Manifest packages must be an array")
		return
	var packages: Array = packages_value
	if packages.size() != Contract.ACTIVITY_IDS.size():
		_add_issue(issues, "SCHEMA_SIZE", ["packages"], "Manifest requires all eleven activity packages")
	var paths := {}
	for index in packages.size():
		var entry_value: Variant = packages[index]
		if not entry_value is Dictionary:
			_add_issue(issues, "SCHEMA_TYPE", ["packages", index], "Manifest entry must be an object")
			continue
		var entry: Dictionary = entry_value
		var path: Array = ["packages", index]
		_expect_exact_keys(entry, Contract.MANIFEST_ENTRY_KEYS, [], path, issues)
		var activity_id := String(entry.get("activity_id", ""))
		if activity_id not in Contract.ACTIVITY_IDS:
			_add_issue(issues, "UNKNOWN_ACTIVITY_ID", path + ["activity_id"], "Manifest activity is not allowlisted")
		elif index >= Contract.ACTIVITY_IDS.size() or activity_id != Contract.ACTIVITY_IDS[index]:
			_add_issue(issues, "MANIFEST_PACKAGE_ORDER", path + ["activity_id"], "Manifest entries must follow catalogue order")
		var version_value: Variant = entry.get("content_version")
		if not _is_semantic_version(version_value):
			_add_issue(issues, "SEMANTIC_VERSION", path + ["content_version"], "Manifest content version must be semantic")
		var package_path := String(entry.get("path", ""))
		var expected_path := "content/packages/%s/%s.json" % [activity_id, String(version_value)]
		if package_path != expected_path:
			_add_issue(issues, "MANIFEST_PACKAGE_PATH", path + ["path"], "Manifest package path must match its identity")
		if paths.has(package_path):
			_add_issue(issues, "MANIFEST_DUPLICATE_PATH", path + ["path"], "Manifest package paths must be unique")
		paths[package_path] = true
		if not _is_checksum(entry.get("checksum")):
			_add_issue(issues, "CHECKSUM_FORMAT", path + ["checksum"], "Manifest checksum is malformed")

func _expect_exact_keys(
	value: Dictionary,
	required: Array,
	optional: Array,
	path: Array,
	issues: Array[Dictionary]
) -> void:
	for key in required:
		if not value.has(key):
			_add_issue(issues, "SCHEMA_MISSING_KEY", path + [key], "Required field is missing")
	for key_value in value.keys():
		if not key_value is String:
			_add_issue(issues, "SCHEMA_KEY_TYPE", path, "Object keys must be strings")
			continue
		var key: String = key_value
		if key in Contract.FORBIDDEN_OBJECT_KEYS:
			_add_issue(issues, "FORBIDDEN_OBJECT_KEY", path + [key], "Reserved object key is forbidden")
		if key not in required and key not in optional:
			_add_issue(issues, "SCHEMA_UNKNOWN_KEY", path + [key], "Unknown field is not allowed")

func _validate_json_domain(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if value == null or value is bool or value is String:
		return
	if typeof(value) == TYPE_INT:
		if not _is_safe_integer(value):
			_add_issue(issues, "UNSAFE_INTEGER", path, "Integer exceeds the cross-language safe range")
		return
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if not is_finite(number):
			_add_issue(issues, "NON_FINITE_NUMBER", path, "Content numbers must be finite")
		elif number == floor(number) and abs(number) > Contract.SAFE_INTEGER_MAX:
			_add_issue(issues, "UNSAFE_INTEGER", path, "Integer exceeds the cross-language safe range")
		return
	if value is Array:
		var values: Array = value
		for index in values.size():
			_validate_json_domain(values[index], path + [index], issues)
		return
	if value is Dictionary:
		var object: Dictionary = value
		for key_value in object.keys():
			if not key_value is String:
				_add_issue(issues, "SCHEMA_KEY_TYPE", path, "JSON object keys must be strings")
				continue
			var key: String = key_value
			if key in Contract.FORBIDDEN_OBJECT_KEYS:
				_add_issue(issues, "FORBIDDEN_OBJECT_KEY", path + [key], "Reserved object key is forbidden")
			_validate_json_domain(object[key], path + [key], issues)
		return
	_add_issue(issues, "UNSUPPORTED_TYPE", path, "Value is not representable in JSON")

func _encode_canonical(value: Variant, depth: int, omit_checksum: bool, state: Dictionary) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is String:
		if not _is_well_formed_unicode(value):
			state["ok"] = false
			return ""
		return JSON.stringify(value)
	if typeof(value) == TYPE_INT:
		if not _is_safe_integer(value):
			state["ok"] = false
			return ""
		return str(value)
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if not is_finite(number):
			state["ok"] = false
			return ""
		if number == floor(number):
			if abs(number) > Contract.SAFE_INTEGER_MAX:
				state["ok"] = false
				return ""
			return str(int(number))
		return _encode_ecmascript_number(number)
	if value is Array:
		var items: Array[String] = []
		var array: Array = value
		for item in array:
			items.append(_encode_canonical(item, depth + 1, omit_checksum, state))
		return "[%s]" % ",".join(items)
	if value is Dictionary:
		var object: Dictionary = value
		var keys: Array[String] = []
		for key_value in object.keys():
			if not key_value is String:
				state["ok"] = false
				return ""
			var key: String = key_value
			if not _is_well_formed_unicode(key):
				state["ok"] = false
				return ""
			if depth == 0 and omit_checksum and key == "checksum":
				continue
			keys.append(key)
		keys.sort_custom(_utf16_key_less)
		var entries: Array[String] = []
		for key in keys:
			entries.append("%s:%s" % [JSON.stringify(key), _encode_canonical(object[key], depth + 1, omit_checksum, state)])
		return "{%s}" % ",".join(entries)
	state["ok"] = false
	return ""

func _encode_ecmascript_number(number: float) -> String:
	var encoded := JSON.stringify(number, "", true, true).to_lower()
	if number == 0.0:
		return "0"
	if "e" in encoded:
		var normalized := _normalize_scientific_exponent(encoded)
		var exponent := int(normalized.get_slice("e", 1))
		if exponent >= -6 and exponent < 21:
			return _scientific_to_decimal(normalized)
		return normalized
	if abs(number) >= 0.000001:
		return encoded

	var sign := ""
	var unsigned := encoded
	if unsigned.begins_with("-"):
		sign = "-"
		unsigned = unsigned.substr(1)
	var decimal_index := unsigned.find(".")
	if decimal_index < 0:
		decimal_index = unsigned.length()
	var digits := unsigned.replace(".", "")
	var first_nonzero := 0
	while first_nonzero < digits.length() and digits[first_nonzero] == "0":
		first_nonzero += 1
	if first_nonzero == digits.length():
		return "0"
	var exponent := decimal_index - first_nonzero - 1
	var significant := digits.substr(first_nonzero).rstrip("0")
	var mantissa := significant[0]
	if significant.length() > 1:
		mantissa += ".%s" % significant.substr(1)
	return "%s%se%d" % [sign, mantissa, exponent]

func _scientific_to_decimal(encoded: String) -> String:
	var parts := encoded.split("e", true, 1)
	if parts.size() != 2:
		return encoded
	var mantissa := String(parts[0])
	var sign := ""
	if mantissa.begins_with("-"):
		sign = "-"
		mantissa = mantissa.substr(1)
	var decimal_index := mantissa.find(".")
	if decimal_index < 0:
		decimal_index = mantissa.length()
	var digits := mantissa.replace(".", "")
	var decimal_position := decimal_index + int(parts[1])
	if decimal_position <= 0:
		return "%s0.%s%s" % [sign, "0".repeat(-decimal_position), digits]
	if decimal_position >= digits.length():
		return "%s%s%s" % [sign, digits, "0".repeat(decimal_position - digits.length())]
	return "%s%s.%s" % [
		sign,
		digits.substr(0, decimal_position),
		digits.substr(decimal_position),
	]

func _normalize_scientific_exponent(encoded: String) -> String:
	var parts := encoded.split("e", false, 1)
	if parts.size() != 2:
		return encoded
	var exponent := int(parts[1])
	var exponent_text := "+%d" % exponent if exponent >= 0 else str(exponent)
	return "%se%s" % [parts[0].rstrip("0").rstrip("."), exponent_text]

func _sha256(source: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(source.to_utf8_buffer()) != OK:
		return ""
	return "%s%s" % [Contract.CHECKSUM_PREFIX, context.finish().hex_encode()]

func _scan_value(state: Dictionary, path: Array, depth: int) -> bool:
	if depth > Contract.MAX_JSON_NESTING:
		_add_issue(state["issues"], "NESTING_TOO_DEEP", path, "JSON nesting exceeds the content limit")
		return false
	_skip_whitespace(state)
	var source: String = state["source"]
	var index: int = state["index"]
	if index >= source.length():
		_add_issue(state["issues"], "INVALID_JSON", path, "Expected a JSON value")
		return false
	var character := source[index]
	if character == "{":
		return _scan_object(state, path, depth)
	if character == "[":
		return _scan_array(state, path, depth)
	if character == "\"":
		return bool(_scan_string(state, path)["ok"])
	if character == "-" or (character >= "0" and character <= "9"):
		return _scan_number(state, path)
	for literal in ["true", "false", "null"]:
		if source.substr(index, literal.length()) == literal:
			state["index"] = index + literal.length()
			return true
	_add_issue(state["issues"], "INVALID_JSON", path, "Expected a JSON value")
	return false

func _scan_object(state: Dictionary, path: Array, depth: int) -> bool:
	state["index"] = int(state["index"]) + 1
	_skip_whitespace(state)
	var source: String = state["source"]
	if int(state["index"]) < source.length() and source[int(state["index"])] == "}":
		state["index"] = int(state["index"]) + 1
		return true
	var keys := {}
	while int(state["index"]) < source.length():
		_skip_whitespace(state)
		if int(state["index"]) >= source.length() or source[int(state["index"])] != "\"":
			_add_issue(state["issues"], "INVALID_JSON", path, "Expected a quoted object key")
			return false
		var key_result := _scan_string(state, path)
		if not bool(key_result["ok"]):
			return false
		var key: String = key_result["value"]
		if keys.has(key):
			_add_issue(state["issues"], "DUPLICATE_KEY", path + [key], "Duplicate object key")
			return false
		keys[key] = true
		_skip_whitespace(state)
		if int(state["index"]) >= source.length() or source[int(state["index"])] != ":":
			_add_issue(state["issues"], "INVALID_JSON", path + [key], "Expected ':' after object key")
			return false
		state["index"] = int(state["index"]) + 1
		if not _scan_value(state, path + [key], depth + 1):
			return false
		_skip_whitespace(state)
		if int(state["index"]) >= source.length():
			break
		var separator := source[int(state["index"])]
		if separator == "}":
			state["index"] = int(state["index"]) + 1
			return true
		if separator != ",":
			_add_issue(state["issues"], "INVALID_JSON", path, "Expected ',' or '}' in object")
			return false
		state["index"] = int(state["index"]) + 1
	_add_issue(state["issues"], "INVALID_JSON", path, "Unterminated object")
	return false

func _scan_array(state: Dictionary, path: Array, depth: int) -> bool:
	state["index"] = int(state["index"]) + 1
	_skip_whitespace(state)
	var source: String = state["source"]
	if int(state["index"]) < source.length() and source[int(state["index"])] == "]":
		state["index"] = int(state["index"]) + 1
		return true
	var item_index := 0
	while int(state["index"]) < source.length():
		if not _scan_value(state, path + [item_index], depth + 1):
			return false
		item_index += 1
		_skip_whitespace(state)
		if int(state["index"]) >= source.length():
			break
		var separator := source[int(state["index"])]
		if separator == "]":
			state["index"] = int(state["index"]) + 1
			return true
		if separator != ",":
			_add_issue(state["issues"], "INVALID_JSON", path, "Expected ',' or ']' in array")
			return false
		state["index"] = int(state["index"]) + 1
	_add_issue(state["issues"], "INVALID_JSON", path, "Unterminated array")
	return false

func _scan_string(state: Dictionary, path: Array) -> Dictionary:
	var source: String = state["source"]
	var index: int = state["index"] + 1
	var decoded_parts := PackedStringArray()
	while index < source.length():
		var character := source[index]
		if character == "\"":
			state["index"] = index + 1
			return {"ok": true, "value": "".join(decoded_parts)}
		if character.unicode_at(0) < 0x20:
			_add_issue(state["issues"], "INVALID_JSON", path, "Unescaped control character in string")
			return {"ok": false, "value": ""}
		if character.unicode_at(0) == 0xFFFD:
			_add_issue(state["issues"], "INVALID_JSON", path, "Invalid Unicode replacement in JSON string")
			return {"ok": false, "value": ""}
		if character != "\\":
			decoded_parts.append(character)
			index += 1
			continue
		index += 1
		if index >= source.length():
			break
		var escape := source[index]
		var decoded_escape := ""
		match escape:
			"\"": decoded_escape = "\""
			"\\": decoded_escape = "\\"
			"/": decoded_escape = "/"
			"b": decoded_escape = "\b"
			"f": decoded_escape = "\f"
			"n": decoded_escape = "\n"
			"r": decoded_escape = "\r"
			"t": decoded_escape = "\t"
		if not decoded_escape.is_empty():
			decoded_parts.append(decoded_escape)
			index += 1
			continue
		if escape != "u" or index + 4 >= source.length():
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed string escape")
			return {"ok": false, "value": ""}
		var hexadecimal := source.substr(index + 1, 4)
		if not hexadecimal.is_valid_hex_number(false):
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed Unicode escape")
			return {"ok": false, "value": ""}
		var codepoint := hexadecimal.hex_to_int()
		index += 5
		if codepoint >= 0xD800 and codepoint <= 0xDBFF:
			if index + 5 >= source.length() or source.substr(index, 2) != "\\u":
				_add_issue(state["issues"], "INVALID_JSON", path, "Unpaired Unicode surrogate")
				return {"ok": false, "value": ""}
			var low_hex := source.substr(index + 2, 4)
			if not low_hex.is_valid_hex_number(false):
				_add_issue(state["issues"], "INVALID_JSON", path, "Malformed Unicode surrogate")
				return {"ok": false, "value": ""}
			var low := low_hex.hex_to_int()
			if low < 0xDC00 or low > 0xDFFF:
				_add_issue(state["issues"], "INVALID_JSON", path, "Unpaired Unicode surrogate")
				return {"ok": false, "value": ""}
			codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00)
			index += 6
		elif codepoint >= 0xDC00 and codepoint <= 0xDFFF:
			_add_issue(state["issues"], "INVALID_JSON", path, "Unpaired Unicode surrogate")
			return {"ok": false, "value": ""}
		if codepoint == 0xFFFD:
			_add_issue(state["issues"], "INVALID_JSON", path, "Invalid Unicode replacement in JSON escape")
			return {"ok": false, "value": ""}
		decoded_parts.append(String.chr(codepoint))
	_add_issue(state["issues"], "INVALID_JSON", path, "Unterminated string")
	return {"ok": false, "value": ""}

func _scan_number(state: Dictionary, path: Array) -> bool:
	var source: String = state["source"]
	var index: int = state["index"]
	var match_result := _number_pattern.search(source.substr(index))
	if match_result == null:
		_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON number")
		return false
	state["index"] = index + match_result.get_string().length()
	return true

func _skip_whitespace(state: Dictionary) -> void:
	var source: String = state["source"]
	var index: int = state["index"]
	while index < source.length() and source[index] in [" ", "\t", "\r", "\n"]:
		index += 1
	state["index"] = index

func _validate_trimmed_text(value: Variant, maximum: int, path: Array, issues: Array[Dictionary]) -> void:
	if not value is String:
		_add_issue(issues, "SCHEMA_TYPE", path, "Expected text")
		return
	var text: String = value
	if not _is_ecmascript_trimmed(text) or text.length() > maximum:
		_add_issue(issues, "SCHEMA_STRING", path, "Text is empty, padded, or too long")

func _is_ecmascript_trimmed(value: String) -> bool:
	if value.is_empty():
		return false
	return (
		not _is_ecmascript_whitespace(value.unicode_at(0))
		and not _is_ecmascript_whitespace(value.unicode_at(value.length() - 1))
	)

func _is_ecmascript_whitespace(codepoint: int) -> bool:
	return (
		codepoint in [
			0x0009,
			0x000A,
			0x000B,
			0x000C,
			0x000D,
			0x0020,
			0x00A0,
			0x1680,
			0x2028,
			0x2029,
			0x202F,
			0x205F,
			0x3000,
			0xFEFF,
		]
		or (codepoint >= 0x2000 and codepoint <= 0x200A)
	)

func _validate_positive_integer(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not _is_positive_integer(value):
		_add_issue(issues, "SCHEMA_RANGE", path, "Expected a positive safe integer")

func _validate_boolean(value: Variant, path: Array, issues: Array[Dictionary]) -> void:
	if not value is bool:
		_add_issue(issues, "SCHEMA_TYPE", path, "Expected a boolean")

func _is_safe_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= Contract.SAFE_INTEGER_MIN and int(value) <= Contract.SAFE_INTEGER_MAX
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return (
			is_finite(number)
			and number == floor(number)
			and number >= Contract.SAFE_INTEGER_MIN
			and number <= Contract.SAFE_INTEGER_MAX
		)
	return false

func _is_well_formed_unicode(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint == 0xFFFD or (codepoint >= 0xD800 and codepoint <= 0xDFFF):
			return false
	return true

func _utf16_key_less(left: String, right: String) -> bool:
	var left_units := _utf16_code_units(left)
	var right_units := _utf16_code_units(right)
	var shared_length := mini(left_units.size(), right_units.size())
	for index in shared_length:
		if left_units[index] != right_units[index]:
			return left_units[index] < right_units[index]
	return left_units.size() < right_units.size()

func _utf16_code_units(value: String) -> PackedInt32Array:
	var units := PackedInt32Array()
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint <= 0xFFFF:
			units.append(codepoint)
		else:
			var scalar_offset := codepoint - 0x10000
			units.append(0xD800 + (scalar_offset >> 10))
			units.append(0xDC00 + (scalar_offset & 0x3FF))
	return units

func _utf16_length(value: String) -> int:
	var code_units := 0
	for index in value.length():
		code_units += 2 if value.unicode_at(index) > 0xFFFF else 1
	return code_units

func _normalize_json_numbers(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_finite(number) and number == floor(number) and abs(number) <= Contract.SAFE_INTEGER_MAX:
			return int(number)
		return number
	if value is Array:
		var source_array: Array = value
		var normalized_array: Array = []
		for item in source_array:
			normalized_array.append(_normalize_json_numbers(item))
		return normalized_array
	if value is Dictionary:
		var source_object: Dictionary = value
		var normalized_object := {}
		for key in source_object:
			normalized_object[key] = _normalize_json_numbers(source_object[key])
		return normalized_object
	return value

func _is_positive_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and int(value) > 0

func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_safe_integer(value) and int(value) >= 0

func _is_probability(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= 1.0

func _is_semantic_version(value: Variant) -> bool:
	if not value is String:
		return false
	var parts := String(value).split(".", true)
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty() or (part.length() > 1 and part.begins_with("0")):
			return false
		for index in part.length():
			if part[index] < "0" or part[index] > "9":
				return false
	return true

func _is_checksum(value: Variant) -> bool:
	if not value is String:
		return false
	var checksum: String = value
	if not checksum.begins_with(Contract.CHECKSUM_PREFIX):
		return false
	var hexadecimal := checksum.substr(Contract.CHECKSUM_PREFIX.length())
	if hexadecimal.length() != Contract.CHECKSUM_HEX_LENGTH:
		return false
	for index in hexadecimal.length():
		var character := hexadecimal[index]
		if not (character >= "0" and character <= "9") and not (character >= "a" and character <= "f"):
			return false
	return true

func _is_iso_timestamp(value: Variant) -> bool:
	if not value is String:
		return false
	var matched := _timestamp_pattern.search(String(value))
	if matched == null:
		return false
	var year := int(matched.get_string(1))
	var month := int(matched.get_string(2))
	var day := int(matched.get_string(3))
	var hour := int(matched.get_string(4))
	var minute := int(matched.get_string(5))
	var second := int(matched.get_string(6))
	if month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return false
	var month_days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var leap_year := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	if leap_year:
		month_days[1] = 29
	if day < 1 or day > month_days[month - 1]:
		return false
	var offset := matched.get_string(7)
	if offset != "Z":
		var offset_hour := int(offset.substr(1, 2))
		var offset_minute := int(offset.substr(4, 2))
		if offset_hour > 23 or offset_minute > 59:
			return false
	return true

func _same_string_sequence(values: Array, expected: Array) -> bool:
	if values.size() != expected.size():
		return false
	for index in values.size():
		if not values[index] is String or values[index] != expected[index]:
			return false
	return true

func _add_issue(issues: Array[Dictionary], code: String, path: Array, message: String) -> void:
	issues.append({"code": code, "path": path.duplicate(), "message": message})
