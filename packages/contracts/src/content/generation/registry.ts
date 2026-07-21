import { GENERATOR_IDS, type GeneratorId } from "../ids.js";
import type {
  GeneratedQuestionFields,
  GeneratorValidationResult,
  QuestionGeneratorContract,
} from "./types.js";
import { AdditionGenerator, MultiplicationGenerator, SubtractionGenerator } from "./arithmetic.js";

class PendingQuestionGenerator implements QuestionGeneratorContract {
  readonly generatorId: GeneratorId;
  readonly lastError = "GENERATOR_NOT_IMPLEMENTED";

  constructor(generatorId: GeneratorId) {
    this.generatorId = generatorId;
  }

  validateParameters(_parameters: Readonly<Record<string, unknown>>): GeneratorValidationResult {
    return { valid: false, issues: ["GENERATOR_NOT_IMPLEMENTED"] };
  }

  generate(): GeneratedQuestionFields | null {
    return null;
  }
}

type GeneratorFactory = () => QuestionGeneratorContract;

const GENERATOR_FACTORIES: Readonly<Record<GeneratorId, GeneratorFactory>> = {
  addition_v1: () => new AdditionGenerator(),
  subtraction_v1: () => new SubtractionGenerator(),
  multiplication_v1: () => new MultiplicationGenerator(),
  common_multiple_v1: () => new PendingQuestionGenerator("common_multiple_v1"),
  prime_factorization_v1: () => new PendingQuestionGenerator("prime_factorization_v1"),
  counting_v1: () => new PendingQuestionGenerator("counting_v1"),
  number_bonds_v1: () => new PendingQuestionGenerator("number_bonds_v1"),
  ten_frame_v1: () => new PendingQuestionGenerator("ten_frame_v1"),
  base_ten_v1: () => new PendingQuestionGenerator("base_ten_v1"),
  number_line_v1: () => new PendingQuestionGenerator("number_line_v1"),
  basic_operations_v1: () => new PendingQuestionGenerator("basic_operations_v1"),
};

export class GeneratorRegistry {
  create(generatorId: string): QuestionGeneratorContract | null {
    if (!(GENERATOR_IDS as readonly string[]).includes(generatorId)) return null;
    return GENERATOR_FACTORIES[generatorId as GeneratorId]();
  }
}
