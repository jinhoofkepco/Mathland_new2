export const EXPRESSION_SAFE_INTEGER_MAX = 9_007_199_254_740_991n;
export const EXPRESSION_SAFE_INTEGER_MIN = -EXPRESSION_SAFE_INTEGER_MAX;
export const EXPRESSION_MAX_SOURCE_LENGTH = 512;
export const EXPRESSION_MAX_TOKENS = 128;

export type ExpressionErrorCode =
  | "EMPTY"
  | "INVALID_TOKEN"
  | "UNKNOWN_IDENTIFIER"
  | "UNKNOWN_FUNCTION"
  | "ARITY"
  | "DIVIDE_BY_ZERO"
  | "NON_INTEGRAL_DIVISION"
  | "DIGIT_RANGE"
  | "OVERFLOW"
  | "TOO_COMPLEX"
  | "TRAILING_INPUT";

export interface ExpressionFailure {
  ok: false;
  value: 0;
  error_code: ExpressionErrorCode;
  offset: number;
}

export function expressionFailure(
  error_code: ExpressionErrorCode,
  offset: number,
): ExpressionFailure {
  return { ok: false, value: 0, error_code, offset };
}

export type ExpressionTokenKind =
  | "integer"
  | "identifier"
  | "plus"
  | "minus"
  | "star"
  | "slash"
  | "percent"
  | "left_paren"
  | "right_paren"
  | "comma"
  | "eof";

export interface ExpressionToken {
  kind: ExpressionTokenKind;
  lexeme: string;
  offset: number;
}

export type TokenizeExpressionResult =
  | { ok: true; tokens: ExpressionToken[] }
  | ExpressionFailure;

const SINGLE_CHARACTER_TOKENS: Readonly<Record<string, ExpressionTokenKind>> = {
  "+": "plus",
  "-": "minus",
  "*": "star",
  "/": "slash",
  "%": "percent",
  "(": "left_paren",
  ")": "right_paren",
  ",": "comma",
};

function isAsciiDigit(character: string): boolean {
  return character >= "0" && character <= "9";
}

function isIdentifierStart(character: string): boolean {
  return (
    (character >= "A" && character <= "Z") ||
    (character >= "a" && character <= "z") ||
    character === "_"
  );
}

function isIdentifierContinue(character: string): boolean {
  return isIdentifierStart(character) || isAsciiDigit(character);
}

function isWhitespace(character: string): boolean {
  return character === " " || character === "\t" || character === "\n" || character === "\r";
}

export function tokenizeExpression(source: string): TokenizeExpressionResult {
  if (source.length > EXPRESSION_MAX_SOURCE_LENGTH) {
    return expressionFailure("TOO_COMPLEX", EXPRESSION_MAX_SOURCE_LENGTH);
  }

  const tokens: ExpressionToken[] = [];
  let index = 0;
  const pushToken = (kind: ExpressionTokenKind, start: number, end: number): ExpressionFailure | null => {
    if (tokens.length >= EXPRESSION_MAX_TOKENS) {
      return expressionFailure("TOO_COMPLEX", start);
    }
    tokens.push({ kind, lexeme: source.slice(start, end), offset: start });
    return null;
  };

  while (index < source.length) {
    const character = source[index] ?? "";
    if (isWhitespace(character)) {
      index += 1;
      continue;
    }

    const singleKind = SINGLE_CHARACTER_TOKENS[character];
    if (singleKind !== undefined) {
      const failure = pushToken(singleKind, index, index + 1);
      if (failure !== null) return failure;
      index += 1;
      continue;
    }

    if (isAsciiDigit(character)) {
      const start = index;
      do {
        index += 1;
      } while (index < source.length && isAsciiDigit(source[index] ?? ""));
      const failure = pushToken("integer", start, index);
      if (failure !== null) return failure;
      continue;
    }

    if (isIdentifierStart(character)) {
      const start = index;
      do {
        index += 1;
      } while (index < source.length && isIdentifierContinue(source[index] ?? ""));
      const failure = pushToken("identifier", start, index);
      if (failure !== null) return failure;
      continue;
    }

    return expressionFailure("INVALID_TOKEN", index);
  }

  if (tokens.length === 0) {
    return expressionFailure("EMPTY", 0);
  }
  tokens.push({ kind: "eof", lexeme: "", offset: source.length });
  return { ok: true, tokens };
}
