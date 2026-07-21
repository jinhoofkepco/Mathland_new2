class_name GeneratorRegistry
extends RefCounted

const QuestionGeneratorScript = preload("res://src/content/generation/question_generator.gd")
const AdditionGeneratorScript = preload("res://src/content/generation/generators/addition_generator.gd")
const SubtractionGeneratorScript = preload("res://src/content/generation/generators/subtraction_generator.gd")
const MultiplicationGeneratorScript = preload("res://src/content/generation/generators/multiplication_generator.gd")
const CommonMultipleGeneratorScript = preload("res://src/content/generation/generators/common_multiple_generator.gd")
const PrimeFactorizationGeneratorScript = preload("res://src/content/generation/generators/prime_factorization_generator.gd")
const CountingGeneratorScript = preload("res://src/content/generation/generators/counting_generator.gd")
const NumberBondGeneratorScript = preload("res://src/content/generation/generators/number_bond_generator.gd")
const TenFrameGeneratorScript = preload("res://src/content/generation/generators/ten_frame_generator.gd")
const BaseTenGeneratorScript = preload("res://src/content/generation/generators/base_ten_generator.gd")
const NumberLineGeneratorScript = preload("res://src/content/generation/generators/number_line_generator.gd")
const BasicOperationsGeneratorScript = preload("res://src/content/generation/generators/basic_operations_generator.gd")

const GENERATORS := {
	"addition_v1": AdditionGeneratorScript,
	"subtraction_v1": SubtractionGeneratorScript,
	"multiplication_v1": MultiplicationGeneratorScript,
	"common_multiple_v1": CommonMultipleGeneratorScript,
	"prime_factorization_v1": PrimeFactorizationGeneratorScript,
	"counting_v1": CountingGeneratorScript,
	"number_bonds_v1": NumberBondGeneratorScript,
	"ten_frame_v1": TenFrameGeneratorScript,
	"base_ten_v1": BaseTenGeneratorScript,
	"number_line_v1": NumberLineGeneratorScript,
	"basic_operations_v1": BasicOperationsGeneratorScript,
}

func create(generator_id: String) -> Variant:
	var generator_script: Variant = GENERATORS.get(generator_id)
	return generator_script.new() if generator_script != null else null
