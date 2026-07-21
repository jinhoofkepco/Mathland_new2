import {
  EXPRESSION_SAFE_INTEGER_MAX,
  expressionFailure,
  type ExpressionFailure,
  type ExpressionToken,
  type ExpressionTokenKind,
} from "./tokens.js";

export type BinaryOperator = "+" | "-" | "*" | "/" | "%";

export type ExpressionNode =
  | { kind: "integer"; value: bigint; offset: number }
  | { kind: "variable"; name: string; offset: number }
  | { kind: "unary"; operand: ExpressionNode; offset: number }
  | {
      kind: "binary";
      operator: BinaryOperator;
      left: ExpressionNode;
      right: ExpressionNode;
      offset: number;
    }
  | { kind: "call"; name: string; arguments: ExpressionNode[]; offset: number };

export type ParseExpressionResult = { ok: true; expression: ExpressionNode } | ExpressionFailure;

const MAX_NESTING = 16;

class Parser {
  readonly #tokens: ExpressionToken[];
  #current = 0;
  #failure: ExpressionFailure | null = null;

  constructor(tokens: ExpressionToken[]) {
    this.#tokens = tokens;
  }

  parse(): ParseExpressionResult {
    const expression = this.#parseAdditive(0);
    if (this.#failure !== null) return this.#failure;
    if (expression === null) return expressionFailure("INVALID_TOKEN", this.#peek().offset);
    if (!this.#check("eof")) return expressionFailure("TRAILING_INPUT", this.#peek().offset);
    return { ok: true, expression };
  }

  #parseAdditive(depth: number): ExpressionNode | null {
    let expression = this.#parseMultiplicative(depth);
    while (this.#failure === null && expression !== null && this.#match("plus", "minus")) {
      const operator = this.#previous();
      const right = this.#parseMultiplicative(depth);
      if (right === null) return null;
      expression = {
        kind: "binary",
        operator: operator.kind === "plus" ? "+" : "-",
        left: expression,
        right,
        offset: operator.offset,
      };
    }
    return expression;
  }

  #parseMultiplicative(depth: number): ExpressionNode | null {
    let expression = this.#parseUnary(depth);
    while (
      this.#failure === null &&
      expression !== null &&
      this.#match("star", "slash", "percent")
    ) {
      const operator = this.#previous();
      const right = this.#parseUnary(depth);
      if (right === null) return null;
      const symbols: Record<"star" | "slash" | "percent", BinaryOperator> = {
        star: "*",
        slash: "/",
        percent: "%",
      };
      expression = {
        kind: "binary",
        operator: symbols[operator.kind as "star" | "slash" | "percent"],
        left: expression,
        right,
        offset: operator.offset,
      };
    }
    return expression;
  }

  #parseUnary(depth: number): ExpressionNode | null {
    if (!this.#match("minus")) return this.#parsePrimary(depth);
    const operator = this.#previous();
    if (depth >= MAX_NESTING) {
      this.#failure = expressionFailure("TOO_COMPLEX", operator.offset);
      return null;
    }
    const operand = this.#parseUnary(depth + 1);
    if (operand === null) return null;
    return { kind: "unary", operand, offset: operator.offset };
  }

  #parsePrimary(depth: number): ExpressionNode | null {
    if (this.#match("integer")) {
      const token = this.#previous();
      const value = BigInt(token.lexeme);
      if (value > EXPRESSION_SAFE_INTEGER_MAX) {
        this.#failure = expressionFailure("OVERFLOW", token.offset);
        return null;
      }
      return { kind: "integer", value, offset: token.offset };
    }

    if (this.#match("identifier")) {
      const identifier = this.#previous();
      if (!this.#match("left_paren")) {
        return { kind: "variable", name: identifier.lexeme, offset: identifier.offset };
      }
      if (depth >= MAX_NESTING) {
        this.#failure = expressionFailure("TOO_COMPLEX", identifier.offset);
        return null;
      }
      const arguments_: ExpressionNode[] = [];
      if (!this.#check("right_paren")) {
        while (true) {
          const argument = this.#parseAdditive(depth + 1);
          if (argument === null) return null;
          arguments_.push(argument);
          if (!this.#match("comma")) break;
        }
      }
      if (!this.#match("right_paren")) {
        this.#failure = expressionFailure("INVALID_TOKEN", this.#peek().offset);
        return null;
      }
      return { kind: "call", name: identifier.lexeme, arguments: arguments_, offset: identifier.offset };
    }

    if (this.#match("left_paren")) {
      const leftParen = this.#previous();
      if (depth >= MAX_NESTING) {
        this.#failure = expressionFailure("TOO_COMPLEX", leftParen.offset);
        return null;
      }
      const expression = this.#parseAdditive(depth + 1);
      if (expression === null) return null;
      if (!this.#match("right_paren")) {
        this.#failure = expressionFailure("INVALID_TOKEN", this.#peek().offset);
        return null;
      }
      return expression;
    }

    this.#failure = expressionFailure("INVALID_TOKEN", this.#peek().offset);
    return null;
  }

  #match(...kinds: ExpressionTokenKind[]): boolean {
    for (const kind of kinds) {
      if (this.#check(kind)) {
        this.#current += 1;
        return true;
      }
    }
    return false;
  }

  #check(kind: ExpressionTokenKind): boolean {
    return this.#peek().kind === kind;
  }

  #peek(): ExpressionToken {
    return this.#tokens[this.#current] ?? this.#tokens[this.#tokens.length - 1]!;
  }

  #previous(): ExpressionToken {
    return this.#tokens[this.#current - 1]!;
  }
}

export function parseExpressionTokens(tokens: ExpressionToken[]): ParseExpressionResult {
  return new Parser(tokens).parse();
}
