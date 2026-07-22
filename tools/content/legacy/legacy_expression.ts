import {
  parseExpressionTokens,
  tokenizeExpression,
  type ExpressionNode,
} from "../../../packages/contracts/src/index.js";

const LEGACY_FUNCTIONS: Readonly<Record<string, string>> = {
  Mod: "mod",
  Quotient: "quotient",
  digit: "digit",
  gcd: "gcd",
  lcm: "lcm",
};

const MAX_LEGACY_EXPRESSION_LENGTH = 512;
const MAX_NESTING = 16;

interface Delimiter {
  kind: "parenthesis" | "function";
  separator_count: number;
  offset: number;
}

function isAsciiLetter(character: string): boolean {
  return (
    (character >= "A" && character <= "Z") ||
    (character >= "a" && character <= "z")
  );
}

function isAsciiDigit(character: string): boolean {
  return character >= "0" && character <= "9";
}

function isIdentifierContinue(character: string): boolean {
  return isAsciiLetter(character) || isAsciiDigit(character) || character === "_";
}

function isWhitespace(character: string): boolean {
  return character === " " || character === "\t" || character === "\r" || character === "\n";
}

function isAllowedVariable(identifier: string): boolean {
  if (identifier === "answer" || identifier === "sub_level") return true;
  return identifier.length === 1 && identifier >= "A" && identifier <= "Z";
}

function skipWhitespace(source: string, start: number): number {
  let index = start;
  while (index < source.length && isWhitespace(source[index] ?? "")) index += 1;
  return index;
}

function assertFunctionArities(node: ExpressionNode): void {
  switch (node.kind) {
    case "integer":
    case "variable":
      return;
    case "unary":
      assertFunctionArities(node.operand);
      return;
    case "binary":
      assertFunctionArities(node.left);
      assertFunctionArities(node.right);
      return;
    case "call":
      if (node.arguments.length !== 2) {
        throw new Error(`Legacy function ${node.name} requires exactly two arguments`);
      }
      for (const argument of node.arguments) assertFunctionArities(argument);
  }
}

export function translateLegacyExpression(rawSource: string): string {
  if (typeof rawSource !== "string" || rawSource.length === 0) {
    throw new Error("Legacy expression must be a nonempty string");
  }
  if (rawSource.length > MAX_LEGACY_EXPRESSION_LENGTH) {
    throw new Error("Legacy expression exceeds the development conversion limit");
  }

  let source = rawSource.trim();
  if (source.startsWith("(answer)")) source = source.slice("(answer)".length).trimStart();
  if (source.length === 0) throw new Error("Computed legacy component has no expression");

  const output: string[] = [];
  const delimiters: Delimiter[] = [];
  let index = 0;

  while (index < source.length) {
    const character = source[index] ?? "";
    if (isWhitespace(character)) {
      index += 1;
      continue;
    }

    if (source.startsWith("(sub_level)", index)) {
      output.push("sub_level");
      index += "(sub_level)".length;
      continue;
    }

    if (isAsciiDigit(character)) {
      const start = index;
      do index += 1;
      while (index < source.length && isAsciiDigit(source[index] ?? ""));
      output.push(source.slice(start, index));
      continue;
    }

    if (isAsciiLetter(character) || character === "_") {
      const start = index;
      do index += 1;
      while (index < source.length && isIdentifierContinue(source[index] ?? ""));
      const identifier = source.slice(start, index);
      const next = skipWhitespace(source, index);
      if (source[next] === "[") {
        const canonical = LEGACY_FUNCTIONS[identifier];
        if (canonical === undefined) {
          throw new Error(`Unsupported legacy function ${identifier} at offset ${start}`);
        }
        if (delimiters.length >= MAX_NESTING) throw new Error("Legacy expression is too deeply nested");
        output.push(canonical, "(");
        delimiters.push({ kind: "function", separator_count: 0, offset: next });
        index = next + 1;
        continue;
      }
      if (!isAllowedVariable(identifier)) {
        throw new Error(`Unsupported legacy identifier ${identifier} at offset ${start}`);
      }
      output.push(identifier);
      continue;
    }

    if (character === "(") {
      if (delimiters.length >= MAX_NESTING) throw new Error("Legacy expression is too deeply nested");
      output.push(character);
      delimiters.push({ kind: "parenthesis", separator_count: 0, offset: index });
      index += 1;
      continue;
    }
    if (character === ")") {
      const delimiter = delimiters.pop();
      if (delimiter?.kind !== "parenthesis") {
        throw new Error(`Unbalanced parenthesis at offset ${index}`);
      }
      output.push(character);
      index += 1;
      continue;
    }
    if (character === "~") {
      const delimiter = delimiters[delimiters.length - 1];
      if (delimiter?.kind !== "function" || delimiter.separator_count !== 0) {
        throw new Error(`Unexpected legacy argument separator at offset ${index}`);
      }
      delimiter.separator_count += 1;
      output.push(",");
      index += 1;
      continue;
    }
    if (character === "]") {
      const delimiter = delimiters.pop();
      if (delimiter?.kind !== "function") {
        throw new Error(`Unbalanced legacy function bracket at offset ${index}`);
      }
      if (delimiter.separator_count !== 1) {
        throw new Error(`Legacy function at offset ${delimiter.offset} requires two arguments`);
      }
      output.push(")");
      index += 1;
      continue;
    }
    if (character === "+" || character === "-" || character === "*" || character === "/" || character === "%") {
      output.push(character);
      index += 1;
      continue;
    }

    throw new Error(`Unsafe legacy expression character at offset ${index}`);
  }

  if (delimiters.length > 0) {
    throw new Error(`Unbalanced legacy expression delimiter at offset ${delimiters[0]!.offset}`);
  }

  const canonical = output.join("");
  const tokenized = tokenizeExpression(canonical);
  if (!tokenized.ok) {
    throw new Error(`Invalid translated expression: ${tokenized.error_code} at ${tokenized.offset}`);
  }
  const parsed = parseExpressionTokens(tokenized.tokens);
  if (!parsed.ok) {
    throw new Error(`Invalid translated expression: ${parsed.error_code} at ${parsed.offset}`);
  }
  assertFunctionArities(parsed.expression);
  return canonical;
}
