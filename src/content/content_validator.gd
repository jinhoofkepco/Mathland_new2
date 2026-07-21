class_name ContentValidator
extends RefCounted

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const ValidationResult = preload("res://src/content/content_validation_result.gd")
const BIG_INTEGER_BASE := 1000000000
const DOUBLE_HIDDEN_BIT := 4503599627370496
const UINT32_SCALE := 4294967296
const DECIMAL_SEED_MIN := 10000000000000000
const DECIMAL_SEED_MAX := 99999999999999999
const MAX_EXACT_BINARY_INTEGER := 4503599627370496
const MIN_NORMAL_DOUBLE := 2.2250738585072014e-308

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
	if not _validate_canonical_domain_iterative(value):
		return ""
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
	if value == null or value is bool:
		return
	if value is String:
		if not _is_well_formed_unicode(value):
			_add_issue(issues, "INVALID_UNICODE", path, "Content strings must not contain U+0000 or lossy Unicode")
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
			if not _is_well_formed_unicode(key):
				_add_issue(issues, "INVALID_UNICODE", path + [key], "Content object keys must not contain U+0000 or lossy Unicode")
			if key in Contract.FORBIDDEN_OBJECT_KEYS:
				_add_issue(issues, "FORBIDDEN_OBJECT_KEY", path + [key], "Reserved object key is forbidden")
			_validate_json_domain(object[key], path + [key], issues)
		return
	_add_issue(issues, "UNSUPPORTED_TYPE", path, "Value is not representable in JSON")

func _validate_canonical_domain_iterative(root: Variant) -> bool:
	var active_ancestors: Array = []
	var stack: Array[Dictionary] = [
		{"kind": "visit", "value": root, "path": [], "depth": 0},
	]
	while not stack.is_empty():
		var frame: Dictionary = stack.pop_back()
		if frame["kind"] == "leave":
			for index in range(active_ancestors.size() - 1, -1, -1):
				if is_same(active_ancestors[index], frame["value"]):
					active_ancestors.remove_at(index)
					break
			continue

		var value: Variant = frame["value"]
		var path: Array = frame["path"]
		var depth: int = frame["depth"]
		if depth > Contract.MAX_JSON_NESTING:
			return false
		if value == null or value is bool:
			continue
		if value is String:
			if not _is_well_formed_unicode(value):
				return false
			continue
		if typeof(value) == TYPE_INT:
			if not _is_safe_integer(value):
				return false
			continue
		if typeof(value) == TYPE_FLOAT:
			var number := float(value)
			if not is_finite(number):
				return false
			if number == floor(number) and abs(number) > Contract.SAFE_INTEGER_MAX:
				return false
			continue
		if not value is Array and not value is Dictionary:
			return false

		for ancestor in active_ancestors:
			if is_same(ancestor, value):
				return false
		active_ancestors.append(value)
		stack.append({"kind": "leave", "value": value})
		if value is Array:
			var array: Array = value
			for index in range(array.size() - 1, -1, -1):
				stack.append({
					"kind": "visit",
					"value": array[index],
					"path": path + [index],
					"depth": depth + 1,
				})
		else:
			var object: Dictionary = value
			var keys := object.keys()
			for index in range(keys.size() - 1, -1, -1):
				var key: Variant = keys[index]
				if not key is String or not _is_well_formed_unicode(key):
					return false
				stack.append({
					"kind": "visit",
					"value": object[key],
					"path": path + [key],
					"depth": depth + 1,
				})
	return true

func _encode_canonical(value: Variant, depth: int, omit_checksum: bool, state: Dictionary) -> String:
	if depth > Contract.MAX_JSON_NESTING:
		state["ok"] = false
		return ""
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is String:
		if not _is_well_formed_unicode(value):
			state["ok"] = false
			return ""
		return _encode_ecmascript_string(value)
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
		var encoded_number := _encode_ecmascript_number(number)
		if encoded_number.is_empty():
			state["ok"] = false
		return encoded_number
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
			entries.append("%s:%s" % [_encode_ecmascript_string(key), _encode_canonical(object[key], depth + 1, omit_checksum, state)])
		return "{%s}" % ",".join(entries)
	state["ok"] = false
	return ""

func _encode_ecmascript_string(value: String) -> String:
	var bytes := PackedByteArray()
	bytes.append(0x22)
	for index in value.length():
		_append_ecmascript_codepoint(bytes, value.unicode_at(index))
	bytes.append(0x22)
	return bytes.get_string_from_utf8()

func _append_ecmascript_codepoint(bytes: PackedByteArray, codepoint: int) -> void:
	match codepoint:
		0x22:
			bytes.append(0x5C)
			bytes.append(0x22)
		0x5C:
			bytes.append(0x5C)
			bytes.append(0x5C)
		0x08:
			bytes.append(0x5C)
			bytes.append(0x62)
		0x09:
			bytes.append(0x5C)
			bytes.append(0x74)
		0x0A:
			bytes.append(0x5C)
			bytes.append(0x6E)
		0x0C:
			bytes.append(0x5C)
			bytes.append(0x66)
		0x0D:
			bytes.append(0x5C)
			bytes.append(0x72)
		_ when codepoint < 0x20:
			bytes.append(0x5C)
			bytes.append(0x75)
			bytes.append(0x30)
			bytes.append(0x30)
			bytes.append(_lower_hex_byte(codepoint >> 4))
			bytes.append(_lower_hex_byte(codepoint & 0x0F))
		_:
			_append_utf8_codepoint(bytes, codepoint)

func _lower_hex_byte(nibble: int) -> int:
	return 0x30 + nibble if nibble < 10 else 0x61 + nibble - 10

func _append_utf8_codepoint(bytes: PackedByteArray, codepoint: int) -> void:
	if codepoint <= 0x7F:
		bytes.append(codepoint)
	elif codepoint <= 0x7FF:
		bytes.append(0xC0 | (codepoint >> 6))
		bytes.append(0x80 | (codepoint & 0x3F))
	elif codepoint <= 0xFFFF:
		bytes.append(0xE0 | (codepoint >> 12))
		bytes.append(0x80 | ((codepoint >> 6) & 0x3F))
		bytes.append(0x80 | (codepoint & 0x3F))
	else:
		bytes.append(0xF0 | (codepoint >> 18))
		bytes.append(0x80 | ((codepoint >> 12) & 0x3F))
		bytes.append(0x80 | ((codepoint >> 6) & 0x3F))
		bytes.append(0x80 | (codepoint & 0x3F))

func _encode_ecmascript_number(number: float) -> String:
	if number == 0.0:
		return "0"
	var negative := number < 0.0
	var magnitude: float = absf(number)
	var seed := _exact_decimal_seed(magnitude)
	if seed.is_empty():
		return ""
	var seed_digits: String = seed["digits"]
	var scientific_exponent: int = seed["exponent"]

	for significant_length in range(1, 18):
		var prefix := seed_digits.substr(0, significant_length).to_int()
		var decimal_power := scientific_exponent - significant_length + 1
		var candidates: Array[Dictionary] = []
		var seen := {}
		for adjustment in range(-2, 3):
			var significand := prefix + adjustment
			if significand <= 0 or seen.has(significand):
				continue
			seen[significand] = true
			var candidate_text := _format_decimal_candidate(significand, decimal_power)
			if _decimal_rounds_to_double(significand, decimal_power, magnitude):
				candidates.append({"significand": significand, "text": candidate_text})
		if candidates.is_empty():
			continue
		var closest := _closest_decimal_candidate(magnitude, candidates, decimal_power)
		return ("-" if negative else "") + String(closest["text"])
	return ""

# Computes the first 17 decimal digits from the binary rational itself. The
# logarithm is only a starting estimate; exact comparisons correct the exponent
# and binary-search the prefix without relying on Godot's decimal renderer.
func _exact_decimal_seed(number: float) -> Dictionary:
	var components := _positive_double_components(number)
	var binary_significand: int = components["mantissa"]
	var binary_exponent: int = components["binary_exponent"]
	var scientific_exponent := floori(log(number) / log(10.0))
	while _compare_decimal_to_binary(
		1,
		scientific_exponent,
		binary_significand,
		binary_exponent
	) > 0:
		scientific_exponent -= 1
	while _compare_decimal_to_binary(
		1,
		scientific_exponent + 1,
		binary_significand,
		binary_exponent
	) <= 0:
		scientific_exponent += 1

	var decimal_power := scientific_exponent - 16
	var lower := DECIMAL_SEED_MIN
	var upper := DECIMAL_SEED_MAX
	var prefix := lower
	while lower <= upper:
		@warning_ignore("integer_division")
		var midpoint: int = lower + (upper - lower) / 2
		var comparison := _compare_decimal_to_binary(
			midpoint,
			decimal_power,
			binary_significand,
			binary_exponent
		)
		if comparison <= 0:
			prefix = midpoint
			lower = midpoint + 1
		else:
			upper = midpoint - 1
	return {"digits": str(prefix), "exponent": scientific_exponent}

func _format_decimal_candidate(significand_value: int, decimal_power_value: int) -> String:
	var significand := significand_value
	var decimal_power := decimal_power_value
	while significand % 10 == 0:
		@warning_ignore("integer_division")
		significand /= 10
		decimal_power += 1
	var digits := str(significand)
	var scientific_exponent := decimal_power + digits.length() - 1
	if scientific_exponent >= -6 and scientific_exponent < 21:
		var decimal_position := digits.length() + decimal_power
		if decimal_position <= 0:
			return "0.%s%s" % ["0".repeat(-decimal_position), digits]
		if decimal_position >= digits.length():
			return "%s%s" % [digits, "0".repeat(decimal_position - digits.length())]
		return "%s.%s" % [
			digits.substr(0, decimal_position),
			digits.substr(decimal_position),
		]
	var mantissa := digits[0]
	if digits.length() > 1:
		mantissa += ".%s" % digits.substr(1)
	var exponent_text := "+%d" % scientific_exponent if scientific_exponent >= 0 else str(scientific_exponent)
	return "%se%s" % [mantissa, exponent_text]

func _closest_decimal_candidate(
	number: float,
	candidates: Array[Dictionary],
	decimal_power: int
) -> Dictionary:
	var closest: Dictionary = candidates[0]
	for index in range(1, candidates.size()):
		var candidate: Dictionary = candidates[index]
		var closest_significand: int = closest["significand"]
		var candidate_significand: int = candidate["significand"]
		var midpoint_comparison := _compare_twice_double_to_decimal_sum(
			number,
			closest_significand + candidate_significand,
			decimal_power
		)
		if midpoint_comparison > 0:
			closest = candidate
		elif midpoint_comparison == 0 and candidate_significand % 2 == 0:
			closest = candidate
	return closest

func _decimal_rounds_to_double(
	decimal_significand: int,
	decimal_power: int,
	number: float
) -> bool:
	var components := _positive_double_components(number)
	var mantissa: int = components["mantissa"]
	var binary_exponent: int = components["binary_exponent"]
	var exponent_bits: int = components["exponent_bits"]
	var lower_significand := 2 * mantissa - 1
	var lower_exponent := binary_exponent - 1
	if mantissa == DOUBLE_HIDDEN_BIT and exponent_bits > 1:
		lower_significand = 4 * mantissa - 1
		lower_exponent = binary_exponent - 2
	var upper_significand := 2 * mantissa + 1
	var upper_exponent := binary_exponent - 1
	var lower_comparison := _compare_decimal_to_binary(
		decimal_significand,
		decimal_power,
		lower_significand,
		lower_exponent
	)
	var upper_comparison := _compare_decimal_to_binary(
		decimal_significand,
		decimal_power,
		upper_significand,
		upper_exponent
	)
	var includes_ties := mantissa % 2 == 0
	return (
		(lower_comparison > 0 or (lower_comparison == 0 and includes_ties))
		and (upper_comparison < 0 or (upper_comparison == 0 and includes_ties))
	)

func _compare_decimal_to_binary(
	decimal_significand: int,
	decimal_power: int,
	binary_significand: int,
	binary_exponent: int
) -> int:
	var left := _big_integer_from_int(decimal_significand)
	var right := _big_integer_from_int(binary_significand)
	var common_two_power := mini(decimal_power, binary_exponent)
	var common_five_power := mini(decimal_power, 0)
	_big_integer_multiply_power(left, 2, decimal_power - common_two_power)
	_big_integer_multiply_power(right, 2, binary_exponent - common_two_power)
	_big_integer_multiply_power(left, 5, decimal_power - common_five_power)
	_big_integer_multiply_power(right, 5, -common_five_power)
	return _big_integer_compare(left, right)

func _compare_twice_double_to_decimal_sum(
	number: float,
	decimal_significand_sum: int,
	decimal_power: int
) -> int:
	var components := _positive_double_components(number)
	var left := _big_integer_from_int(components["mantissa"])
	var right := _big_integer_from_int(decimal_significand_sum)
	var left_two_power: int = int(components["binary_exponent"]) + 1
	var right_two_power := decimal_power
	var left_five_power := 0
	var right_five_power := decimal_power
	var common_two_power := mini(left_two_power, right_two_power)
	var common_five_power := mini(left_five_power, right_five_power)
	_big_integer_multiply_power(left, 2, left_two_power - common_two_power)
	_big_integer_multiply_power(right, 2, right_two_power - common_two_power)
	_big_integer_multiply_power(left, 5, left_five_power - common_five_power)
	_big_integer_multiply_power(right, 5, right_five_power - common_five_power)
	return _big_integer_compare(left, right)

func _positive_double_components(number: float) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, number)
	var low_word := bytes.decode_u32(0)
	var high_word := bytes.decode_u32(4)
	var exponent_bits := (high_word >> 20) & 0x7FF
	var fraction := (high_word & 0xFFFFF) * UINT32_SCALE + low_word
	if exponent_bits == 0:
		return {
			"mantissa": fraction,
			"binary_exponent": -1074,
			"exponent_bits": exponent_bits,
		}
	return {
		"mantissa": DOUBLE_HIDDEN_BIT + fraction,
		"binary_exponent": exponent_bits - 1023 - 52,
		"exponent_bits": exponent_bits,
	}

func _big_integer_from_int(source_value: int) -> Array[int]:
	var value := source_value
	var limbs: Array[int] = []
	while value > 0:
		limbs.append(value % BIG_INTEGER_BASE)
		@warning_ignore("integer_division")
		value /= BIG_INTEGER_BASE
	if limbs.is_empty():
		limbs.append(0)
	return limbs

func _big_integer_multiply_power(value: Array[int], factor: int, power: int) -> void:
	for _iteration in power:
		var carry := 0
		for index in value.size():
			var product := value[index] * factor + carry
			value[index] = product % BIG_INTEGER_BASE
			@warning_ignore("integer_division")
			carry = product / BIG_INTEGER_BASE
		if carry > 0:
			value.append(carry)

func _big_integer_compare(left: Array[int], right: Array[int]) -> int:
	if left.size() != right.size():
		return -1 if left.size() < right.size() else 1
	for reverse_index in range(left.size() - 1, -1, -1):
		if left[reverse_index] != right[reverse_index]:
			return -1 if left[reverse_index] < right[reverse_index] else 1
	return 0

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
		return bool(_scan_string(state, path, false)["ok"])
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
		var key_result := _scan_string(state, path, true)
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

func _scan_string(state: Dictionary, path: Array, decode_value: bool) -> Dictionary:
	var source: String = state["source"]
	var start: int = state["index"]
	var index: int = state["index"] + 1
	while index < source.length():
		var character := source[index]
		if character == "\"":
			state["index"] = index + 1
			if not decode_value:
				return {"ok": true, "value": ""}
			var decoded: Variant = JSON.parse_string(source.substr(start, index - start + 1))
			if not decoded is String:
				_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON string")
				return {"ok": false, "value": ""}
			return {"ok": true, "value": decoded}
		var codepoint := character.unicode_at(0)
		if codepoint == 0 or codepoint == 0xFFFD:
			_add_issue(state["issues"], "INVALID_UNICODE", path, "U+0000 and lossy Unicode are not accepted in content JSON")
			return {"ok": false, "value": ""}
		if codepoint < 0x20:
			_add_issue(state["issues"], "INVALID_JSON", path, "Unescaped control character in string")
			return {"ok": false, "value": ""}
		if character != "\\":
			index += 1
			continue
		index += 1
		if index >= source.length():
			break
		var escape := source[index]
		if escape in ["\"", "\\", "/", "b", "f", "n", "r", "t"]:
			index += 1
			continue
		if escape != "u" or index + 4 >= source.length():
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed string escape")
			return {"ok": false, "value": ""}
		var hexadecimal := source.substr(index + 1, 4)
		if not hexadecimal.is_valid_hex_number(false):
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed Unicode escape")
			return {"ok": false, "value": ""}
		codepoint = hexadecimal.hex_to_int()
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
		if codepoint == 0 or codepoint == 0xFFFD:
			_add_issue(state["issues"], "INVALID_UNICODE", path, "U+0000 and lossy Unicode are not accepted in content JSON")
			return {"ok": false, "value": ""}
	_add_issue(state["issues"], "INVALID_JSON", path, "Unterminated string")
	return {"ok": false, "value": ""}

func _scan_number(state: Dictionary, path: Array) -> bool:
	var source: String = state["source"]
	var start: int = state["index"]
	var index: int = start
	if source[index] == "-":
		index += 1
	if index >= source.length():
		_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON number")
		return false
	if source[index] == "0":
		index += 1
	elif source[index] >= "1" and source[index] <= "9":
		index += 1
		while index < source.length() and source[index] >= "0" and source[index] <= "9":
			index += 1
	else:
		_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON number")
		return false
	if index < source.length() and source[index] == ".":
		index += 1
		if index >= source.length() or source[index] < "0" or source[index] > "9":
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON number fraction")
			return false
		while index < source.length() and source[index] >= "0" and source[index] <= "9":
			index += 1
	if index < source.length() and source[index] in ["e", "E"]:
		index += 1
		if index < source.length() and source[index] in ["+", "-"]:
			index += 1
		if index >= source.length() or source[index] < "0" or source[index] > "9":
			_add_issue(state["issues"], "INVALID_JSON", path, "Malformed JSON number exponent")
			return false
		while index < source.length() and source[index] >= "0" and source[index] <= "9":
			index += 1
	var lexeme := source.substr(start, index - start)
	if _decimal_lexeme_adjusted_exponent(lexeme) > 308:
		_add_issue(state["issues"], "NON_FINITE_NUMBER", path, "JSON number exceeds the finite range")
		return false
	if _decimal_lexeme_is_zero(lexeme):
		state["index"] = index
		return true
	var number := lexeme.to_float()
	if not is_finite(number):
		_add_issue(state["issues"], "NON_FINITE_NUMBER", path, "JSON number exceeds the finite range")
		return false
	if number == 0.0 or abs(number) < MIN_NORMAL_DOUBLE:
		_add_issue(
			state["issues"],
			"UNSAFE_INTEGER",
			path,
			"JSON number underflows across supported runtimes"
		)
		return false
	if number == floor(number):
		if abs(number) > Contract.SAFE_INTEGER_MAX:
			_add_issue(
				state["issues"],
				"UNSAFE_INTEGER",
				path,
				"JSON integer exceeds the cross-language safe range"
			)
			return false
		if (
			("." in lexeme and abs(number) > MAX_EXACT_BINARY_INTEGER)
			or not _decimal_lexeme_equals_integer(lexeme, int(number))
		):
			_add_issue(
				state["issues"],
				"UNSAFE_INTEGER",
				path,
				"JSON integer cannot be represented exactly"
			)
			return false
	state["index"] = index
	return true

func _decimal_lexeme_equals_integer(lexeme: String, integer: int) -> bool:
	var source_negative := lexeme.begins_with("-")
	var unsigned := lexeme.substr(1) if source_negative else lexeme
	var exponent_index := unsigned.find("e")
	if exponent_index < 0:
		exponent_index = unsigned.find("E")
	var mantissa := unsigned if exponent_index < 0 else unsigned.substr(0, exponent_index)
	var exponent_source := "0" if exponent_index < 0 else unsigned.substr(exponent_index + 1)
	var decimal_index := mantissa.find(".")
	var fractional_digits := 0 if decimal_index < 0 else mantissa.length() - decimal_index - 1
	var coefficient := _strip_leading_zeroes(mantissa.replace(".", ""))
	if coefficient.is_empty():
		coefficient = "0"
	if coefficient == "0":
		return integer == 0
	if source_negative != (integer < 0):
		return false

	var decimal_power := _parse_capped_decimal_exponent(exponent_source) - fractional_digits
	var target := str(absi(integer))
	if decimal_power >= 0:
		return (
			coefficient.length() + decimal_power == target.length()
			and coefficient + "0".repeat(decimal_power) == target
		)

	var divisor_digits := -decimal_power
	if divisor_digits > coefficient.length():
		return false
	var integer_end := coefficient.length() - divisor_digits
	for index in range(integer_end, coefficient.length()):
		if coefficient[index] != "0":
			return false
	var exact_integer := _strip_leading_zeroes(coefficient.substr(0, integer_end))
	if exact_integer.is_empty():
		exact_integer = "0"
	return exact_integer == target

func _decimal_lexeme_is_zero(lexeme: String) -> bool:
	var unsigned := lexeme.substr(1) if lexeme.begins_with("-") else lexeme
	var exponent_index := unsigned.find("e")
	if exponent_index < 0:
		exponent_index = unsigned.find("E")
	var mantissa := unsigned if exponent_index < 0 else unsigned.substr(0, exponent_index)
	for index in mantissa.length():
		if mantissa[index] >= "1" and mantissa[index] <= "9":
			return false
	return true

func _decimal_lexeme_adjusted_exponent(lexeme: String) -> int:
	var unsigned := lexeme.substr(1) if lexeme.begins_with("-") else lexeme
	var exponent_index := unsigned.find("e")
	if exponent_index < 0:
		exponent_index = unsigned.find("E")
	var mantissa := unsigned if exponent_index < 0 else unsigned.substr(0, exponent_index)
	var exponent_source := "0" if exponent_index < 0 else unsigned.substr(exponent_index + 1)
	var decimal_index := mantissa.find(".")
	var fractional_digits := 0 if decimal_index < 0 else mantissa.length() - decimal_index - 1
	var coefficient := _strip_leading_zeroes(mantissa.replace(".", ""))
	var exponent := _parse_capped_decimal_exponent(exponent_source)
	return exponent if coefficient.is_empty() else exponent - fractional_digits + coefficient.length() - 1

func _parse_capped_decimal_exponent(source: String) -> int:
	var negative := source.begins_with("-")
	var start := 1 if source.begins_with("-") or source.begins_with("+") else 0
	var magnitude := 0
	for index in range(start, source.length()):
		magnitude = magnitude * 10 + source[index].unicode_at(0) - 0x30
		if magnitude > Contract.MAX_JSON_SOURCE_LENGTH:
			return (
				-Contract.MAX_JSON_SOURCE_LENGTH - 1
				if negative
				else Contract.MAX_JSON_SOURCE_LENGTH + 1
			)
	return -magnitude if negative else magnitude

func _strip_leading_zeroes(value: String) -> String:
	var index := 0
	while index < value.length() and value[index] == "0":
		index += 1
	return value.substr(index)

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
		if codepoint == 0 or codepoint == 0xFFFD or (codepoint >= 0xD800 and codepoint <= 0xDFFF):
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
