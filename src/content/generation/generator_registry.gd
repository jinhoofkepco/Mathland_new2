class_name GeneratorRegistry
extends RefCounted

const QuestionGeneratorScript = preload("res://src/content/generation/question_generator.gd")

const GENERATORS := {
	"addition_v1": QuestionGeneratorScript,
	"subtraction_v1": QuestionGeneratorScript,
	"multiplication_v1": QuestionGeneratorScript,
	"common_multiple_v1": QuestionGeneratorScript,
	"prime_factorization_v1": QuestionGeneratorScript,
	"counting_v1": QuestionGeneratorScript,
	"number_bonds_v1": QuestionGeneratorScript,
	"ten_frame_v1": QuestionGeneratorScript,
	"base_ten_v1": QuestionGeneratorScript,
	"number_line_v1": QuestionGeneratorScript,
	"basic_operations_v1": QuestionGeneratorScript,
}

func create(generator_id: String) -> Variant:
	var generator_script: Variant = GENERATORS.get(generator_id)
	return generator_script.new() if generator_script != null else null
