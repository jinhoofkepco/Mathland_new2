class_name ContentValidationResult
extends RefCounted

var ok: bool
var issues: Array[Dictionary]
var value: Variant
var source: String

func _init(
	is_ok: bool = false,
	validation_issues: Array[Dictionary] = [],
	validated_value: Variant = null,
	source_name: String = ""
) -> void:
	ok = is_ok
	issues = validation_issues.duplicate(true)
	value = validated_value.duplicate(true) if validated_value is Dictionary or validated_value is Array else validated_value
	source = source_name

func first_error_code() -> String:
	if issues.is_empty():
		return ""
	return String(issues[0].get("code", ""))
