class_name FoundationGeneratorBase
extends "res://src/content/generation/generators/arithmetic_generator_base.gd"

const MAX_STATE_ITEMS := 128

func _is_safe_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) >= Contract.SAFE_INTEGER_MIN
		and int(value) <= Contract.SAFE_INTEGER_MAX
	)

func _indices(count: int) -> Array[int]:
	var values: Array[int] = []
	for index in count:
		values.append(index)
	return values

func _foundation_fields(
	resolved_parameters: Dictionary,
	prompt_key: String,
	prompt_args: Dictionary,
	answer: int
) -> Dictionary:
	last_error = ""
	return {
		"resolved_parameters": resolved_parameters.duplicate(true),
		"prompt": {"key": prompt_key, "args": prompt_args.duplicate(true)},
		"correct_answer": {"kind": "integer", "value": answer},
	}
