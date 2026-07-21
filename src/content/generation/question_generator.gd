class_name QuestionGenerator
extends RefCounted

var last_error := ""

func validate_parameters(_parameters: Dictionary) -> PackedStringArray:
	return PackedStringArray(["GENERATOR_NOT_IMPLEMENTED"])

func generate(_activity: Dictionary, _band: Dictionary, _seed: int) -> Dictionary:
	return {}
