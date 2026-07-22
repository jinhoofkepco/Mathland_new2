class_name QuestionEngine
extends RefCounted

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")
const UINT32_MAX := 0xFFFFFFFF
const MAX_RESOLVED_ENTRIES := 128
const MAX_RESOLVED_ARRAY_SIZE := 128
const MAX_PROMPT_ARGUMENTS := 32
const MAX_ANSWER_VALUES := 64

var last_diagnostic := ""
var last_diagnostic_detail: Dictionary = {}
var _registry: Variant

func _init(registry: Variant = null) -> void:
	_registry = registry if registry != null else GeneratorRegistryScript.new()

func generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary:
	last_diagnostic = ""
	last_diagnostic_detail = {}
	if seed < 0 or seed > UINT32_MAX:
		return _reject("INVALID_SEED")
	if not _has_valid_identity(activity):
		return _reject("INVALID_ACTIVITY")
	if String(band_id) not in Contract.BAND_IDS:
		return _reject("UNKNOWN_BAND")
	var bands: Variant = activity.get("difficulty_bands")
	if not bands is Array:
		return _reject("INVALID_ACTIVITY")
	var matches: Array[Dictionary] = []
	for band_value in bands:
		if band_value is Dictionary and band_value.get("band_id") == String(band_id):
			matches.append(band_value)
	if matches.is_empty():
		return _reject("UNKNOWN_BAND")
	if matches.size() != 1:
		return _reject("AMBIGUOUS_BAND")
	var band := matches[0]
	var generator_id: Variant = band.get("generator_id")
	if not generator_id is String or generator_id not in Contract.GENERATOR_IDS:
		return _reject("UNKNOWN_GENERATOR")
	var generator: Variant = _registry.create(generator_id)
	if generator == null:
		return _reject("UNKNOWN_GENERATOR")
	var parameters: Variant = band.get("generator_parameters")
	if not parameters is Dictionary:
		return _reject("INVALID_PARAMETERS")
	if not _is_valid_band_metadata(band, generator_id):
		return _reject("INVALID_BAND")
	var issues: PackedStringArray = generator.validate_parameters(parameters.duplicate(true))
	if not issues.is_empty():
		var issue_values: Array[String] = []
		for issue in issues:
			issue_values.append(issue)
		return _reject_with_detail(
			"INVALID_PARAMETERS",
			{"generator_id":generator_id,"issues":issue_values}
		)
	var generated: Variant = generator.generate(activity.duplicate(true), band.duplicate(true), seed)
	var generator_error := String(generator.last_error)
	if generated is Dictionary and generated.is_empty() and not generator_error.is_empty():
		return _reject_with_detail(
			"GENERATOR_FAILED",
			{"generator_id":generator_id,"generator_error":generator_error}
		)
	if not _is_valid_generated(generated):
		return _reject_with_detail(
			"INVALID_GENERATOR_OUTPUT",
			{"generator_id":generator_id,"generator_error":generator_error}
		)
	return {
		"contract_version": 1,
		"activity_id": activity["activity_id"],
		"content_version": activity["content_version"],
		"generator_id": generator_id,
		"band_id": String(band_id),
		"seed": seed,
		"resolved_parameters": generated["resolved_parameters"].duplicate(true),
		"prompt": generated["prompt"].duplicate(true),
		"correct_answer": generated["correct_answer"].duplicate(true),
		"answer_layout": band["answer_layout"].duplicate(true),
		"manipulative": band["manipulative"].duplicate(true),
	}

func _has_valid_identity(activity: Dictionary) -> bool:
	return (
		activity.get("activity_id") is String
		and activity["activity_id"] in Contract.ACTIVITY_IDS
		and activity.get("content_version") is String
		and _is_semantic_version(activity["content_version"])
	)

func _is_valid_generated(generated: Variant) -> bool:
	if not generated is Dictionary:
		return false
	if not _has_exact_keys(generated, ["resolved_parameters", "prompt", "correct_answer"]):
		return false
	return _is_resolved_parameters(generated["resolved_parameters"]) \
		and _is_valid_prompt(generated["prompt"]) \
		and _is_valid_answer(generated["correct_answer"])

func _is_valid_band_metadata(band: Dictionary, generator_id: String) -> bool:
	var layout: Variant = band.get("answer_layout")
	var manipulative: Variant = band.get("manipulative")
	if not layout is Dictionary or not manipulative is Dictionary:
		return false
	if not _has_exact_keys(layout, ["id"]) and not _has_exact_keys(layout, ["id", "options"]):
		return false
	if not layout.get("id") is String or layout["id"] not in Contract.ANSWER_LAYOUT_IDS:
		return false
	if layout.has("options") and not _is_resolved_parameters(layout["options"]):
		return false
	if generator_id == "prime_factorization_v1" and layout["id"] != "factor_slots":
		return false
	if generator_id == "common_multiple_v1" and layout["id"] != "numeric_keypad":
		return false
	if not _has_exact_keys(manipulative, ["id", "config", "initial_state"]):
		return false
	return (
		manipulative.get("id") is String
		and manipulative["id"] in Contract.MANIPULATIVE_IDS
		and _is_resolved_parameters(manipulative.get("config"))
		and _is_resolved_parameters(manipulative.get("initial_state"))
	)

func _is_resolved_parameters(value: Variant) -> bool:
	if not value is Dictionary or value.size() > MAX_RESOLVED_ENTRIES:
		return false
	for key_value in value:
		if not key_value is String or not _is_safe_identifier(key_value):
			return false
		var parameter: Variant = value[key_value]
		if parameter is bool or _is_safe_integer(parameter):
			continue
		if parameter is String and _is_safe_resolved_string(parameter):
			continue
		if parameter is Array:
			if parameter.size() > MAX_RESOLVED_ARRAY_SIZE:
				return false
			for element in parameter:
				if not _is_safe_integer(element):
					return false
			continue
		return false
	return true

func _is_valid_prompt(value: Variant) -> bool:
	if not value is Dictionary or not _has_exact_keys(value, ["key", "args"]):
		return false
	if not value.get("key") is String or not _is_safe_prompt_key(value["key"]):
		return false
	var arguments: Variant = value.get("args")
	if not arguments is Dictionary or arguments.size() > MAX_PROMPT_ARGUMENTS:
		return false
	for key_value in arguments:
		if not key_value is String or not _is_safe_identifier(key_value):
			return false
		var argument: Variant = arguments[key_value]
		if _is_safe_integer(argument):
			continue
		if argument is String and _is_safe_text(argument, 256):
			continue
		return false
	return true

func _is_valid_answer(value: Variant) -> bool:
	if not value is Dictionary or not value.get("kind") is String:
		return false
	if value["kind"] == "integer":
		return _has_exact_keys(value, ["kind", "value"]) and _is_safe_integer(value.get("value"))
	if value["kind"] != "integer_list":
		return false
	if not _has_exact_keys(value, ["kind", "values", "order_matters"]):
		return false
	var values: Variant = value.get("values")
	if not values is Array or values.is_empty() or values.size() > MAX_ANSWER_VALUES:
		return false
	if not value.get("order_matters") is bool:
		return false
	for answer_value in values:
		if not _is_safe_integer(answer_value):
			return false
	return true

func _is_safe_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) >= Contract.SAFE_INTEGER_MIN
		and int(value) <= Contract.SAFE_INTEGER_MAX
	)

func _is_safe_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if index == 0:
			if codepoint < 0x61 or codepoint > 0x7A:
				return false
		elif not (
			(codepoint >= 0x61 and codepoint <= 0x7A)
			or (codepoint >= 0x30 and codepoint <= 0x39)
			or codepoint == 0x5F
		):
			return false
	return true

func _is_safe_prompt_key(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if index == 0 and (codepoint < 0x61 or codepoint > 0x7A):
			return false
		if index > 0 and not (
			(codepoint >= 0x61 and codepoint <= 0x7A)
			or (codepoint >= 0x30 and codepoint <= 0x39)
			or codepoint in [0x2E, 0x5F]
		):
			return false
	return not value.contains("..") and not value.ends_with(".")

func _is_safe_resolved_string(value: String) -> bool:
	return value in ["+", "-", "*", "/", "%"] or _is_safe_identifier(value)

func _is_safe_text(value: String, maximum_length: int) -> bool:
	if value.is_empty() or value.length() > maximum_length or value != value.strip_edges():
		return false
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint < 0x20 or codepoint == 0x7F or codepoint == 0xFFFD:
			return false
	return true

func _is_semantic_version(value: String) -> bool:
	if value.length() > 64:
		return false
	var parts := value.split(".", true)
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty() or (part.length() > 1 and part.begins_with("0")):
			return false
		for index in part.length():
			var codepoint := part.unicode_at(index)
			if codepoint < 0x30 or codepoint > 0x39:
				return false
	return true

func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	var actual: Array[String] = []
	for key_value in value:
		if not key_value is String:
			return false
		actual.append(key_value)
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	return actual == sorted_expected

func _reject(code: String) -> Dictionary:
	return _reject_with_detail(code, {})

func _reject_with_detail(code: String, detail: Dictionary) -> Dictionary:
	last_diagnostic = code
	last_diagnostic_detail = {"code":code}
	for key in detail:
		last_diagnostic_detail[key] = detail[key]
	return {}
