import { GENERATOR_IDS, type GeneratorId } from "../ids.js";
import type { QuestionGeneratorContract } from "./types.js";
import { AdditionGenerator, MultiplicationGenerator, SubtractionGenerator } from "./arithmetic.js";
import { CommonMultipleGenerator, PrimeFactorizationGenerator } from "./number_theory.js";
import {
  BaseTenGenerator,
  BasicOperationsGenerator,
  CountingGenerator,
  NumberBondsGenerator,
  NumberLineGenerator,
  TenFrameGenerator,
} from "./foundations.js";

type GeneratorFactory = () => QuestionGeneratorContract;

const GENERATOR_FACTORIES: Readonly<Record<GeneratorId, GeneratorFactory>> = {
  addition_v1: () => new AdditionGenerator(),
  subtraction_v1: () => new SubtractionGenerator(),
  multiplication_v1: () => new MultiplicationGenerator(),
  common_multiple_v1: () => new CommonMultipleGenerator(),
  prime_factorization_v1: () => new PrimeFactorizationGenerator(),
  counting_v1: () => new CountingGenerator(),
  number_bonds_v1: () => new NumberBondsGenerator(),
  ten_frame_v1: () => new TenFrameGenerator(),
  base_ten_v1: () => new BaseTenGenerator(),
  number_line_v1: () => new NumberLineGenerator(),
  basic_operations_v1: () => new BasicOperationsGenerator(),
};

export class GeneratorRegistry {
  create(generatorId: string): QuestionGeneratorContract | null {
    if (!(GENERATOR_IDS as readonly string[]).includes(generatorId)) return null;
    return GENERATOR_FACTORIES[generatorId as GeneratorId]();
  }
}
