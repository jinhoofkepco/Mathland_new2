import type { GeneratorId } from "../ids.js";
import type { QuestionInstanceV1, ResolvedParametersV1 } from "../types.js";

export interface GeneratedQuestionFields {
  resolved_parameters: ResolvedParametersV1;
  prompt: QuestionInstanceV1["prompt"];
  correct_answer: QuestionInstanceV1["correct_answer"];
}

export interface GeneratorValidationResult {
  valid: boolean;
  issues: readonly string[];
}

export interface QuestionGeneratorContract {
  readonly generatorId: GeneratorId;
  readonly lastError: string;
  validateParameters(parameters: Readonly<ResolvedParametersV1>): GeneratorValidationResult;
  generate(
    activity: Readonly<Record<string, unknown>>,
    band: Readonly<Record<string, unknown>>,
    seed: number,
  ): GeneratedQuestionFields | null;
}
