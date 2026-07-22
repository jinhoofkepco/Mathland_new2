import type { ActivityPackageDraftV1 } from "../../../packages/contracts/src/index.js";

export interface LegacyRange {
  minimum: number;
  maximum: number;
}

export type LegacyQuestionToken =
  | {
      kind: "component";
      component: string;
      qualifier: string | null;
    }
  | {
      kind: "literal";
      value: string;
    };

export interface LegacyField {
  key: string;
  range: LegacyRange | null;
  cells: string[];
  integer_values: number[] | null;
  computed: boolean;
  canonical_expression: string | null;
  question_tokens: LegacyQuestionToken[] | null;
  line: number;
}

export interface LegacyLevel {
  level: number;
  fields: LegacyField[];
  line: number;
}

export interface LegacyDocument {
  source_name: string;
  metadata: LegacyField[];
  levels: LegacyLevel[];
}

export interface LegacyCompatibilityAssertion {
  level: number;
  range: LegacyRange | null;
  source_field: string;
  canonical_expression: string;
}

export interface LegacyConversionResult {
  draft: ActivityPackageDraftV1;
  compatibility_assertions: LegacyCompatibilityAssertion[];
}

export class LegacyFormatError extends Error {
  readonly source_name: string;
  readonly line: number;
  readonly column: number;

  constructor(sourceName: string, line: number, column: number, message: string) {
    super(`${sourceName}:${line}:${column}: ${message}`);
    this.name = "LegacyFormatError";
    this.source_name = sourceName;
    this.line = line;
    this.column = column;
  }
}
