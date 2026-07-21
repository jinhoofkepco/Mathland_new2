class_name QuestionEngine
extends RefCounted

const Contract = preload("res://src/content/generated/content_contract_v1.gd")
const GeneratorRegistryScript = preload("res://src/content/generation/generator_registry.gd")

var last_diagnostic := ""
var _registry: Variant

func _init(registry: Variant = null) -> void:
	_registry = registry if registry != null else GeneratorRegistryScript.new()

func generate_question(activity: Dictionary, band_id: StringName, seed: int) -> Dictionary:
	last_diagnostic = ""
	if seed < 0 or seed > Contract.SAFE_INTEGER_MAX:
		return _reject("INVALID_SEED")
	if not _has_valid_identity(activity):
		return _reject("INVALID_ACTIVITY")
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
	if not generator_id is String:
		return _reject("UNKNOWN_GENERATOR")
	var generator: Variant = _registry.create(generator_id)
	if generator == null:
		return _reject("UNKNOWN_GENERATOR")
	var parameters: Variant = band.get("generator_parameters")
	if not parameters is Dictionary:
		return _reject("INVALID_PARAMETERS")
	if not band.get("answer_layout") is Dictionary or not band.get("manipulative") is Dictionary:
		return _reject("INVALID_BAND")
	var issues: PackedStringArray = generator.validate_parameters(parameters.duplicate(true))
	if not issues.is_empty():
		return _reject("INVALID_PARAMETERS")
	var generated: Variant = generator.generate(activity.duplicate(true), band.duplicate(true), seed)
	if not _is_valid_generated(generated):
		return _reject("INVALID_GENERATOR_OUTPUT")
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
		and not String(activity["activity_id"]).is_empty()
		and activity.get("content_version") is String
		and not String(activity["content_version"]).is_empty()
	)

func _is_valid_generated(generated: Variant) -> bool:
	if not generated is Dictionary:
		return false
	return (
		generated.get("resolved_parameters") is Dictionary
		and generated.get("prompt") is Dictionary
		and generated.get("correct_answer") is Dictionary
	)

func _reject(code: String) -> Dictionary:
	last_diagnostic = code
	return {}
