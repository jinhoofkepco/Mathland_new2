class_name GeneratorRegistry
extends RefCounted

const QuestionGeneratorScript = preload("res://src/content/generation/question_generator.gd")
const AdditionGeneratorScript = preload("res://src/content/generation/generators/addition_generator.gd")
const SubtractionGeneratorScript = preload("res://src/content/generation/generators/subtraction_generator.gd")
const MultiplicationGeneratorScript = preload("res://src/content/generation/generators/multiplication_generator.gd")
const CommonMultipleGeneratorScript = preload("res://src/content/generation/generators/common_multiple_generator.gd")
const PrimeFactorizationGeneratorScript = preload("res://src/content/generation/generators/prime_factorization_generator.gd")

const GENERATORS := {
	"addition_v1": AdditionGeneratorScript,
	"subtraction_v1": SubtractionGeneratorScript,
	"multiplication_v1": MultiplicationGeneratorScript,
	"common_multiple_v1": CommonMultipleGeneratorScript,
	"prime_factorization_v1": PrimeFactorizationGeneratorScript,
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
