import { parseExpressionTokens, type BinaryOperator, type ExpressionNode } from "./parser.js";
import {
  EXPRESSION_SAFE_INTEGER_MAX,
  EXPRESSION_SAFE_INTEGER_MIN,
  expressionFailure,
  tokenizeExpression,
  type ExpressionFailure,
} from "./tokens.js";

export interface ExpressionSuccess {
  ok: true;
  value: number;
  error_code: "";
  offset: -1;
}

export type ExpressionResult = ExpressionSuccess | ExpressionFailure;
export type ExpressionVariables = Readonly<Record<string, number>>;

type InternalResult = { ok: true; value: bigint } | ExpressionFailure;

function success(value: bigint): InternalResult {
  return { ok: true, value };
}

function checked(value: bigint, offset: number): InternalResult {
  if (value < EXPRESSION_SAFE_INTEGER_MIN || value > EXPRESSION_SAFE_INTEGER_MAX) {
    return expressionFailure("OVERFLOW", offset);
  }
  return success(value);
}

function positiveModulo(dividend: bigint, divisor: bigint): bigint {
  const positiveDivisor = divisor < 0n ? -divisor : divisor;
  return ((dividend % positiveDivisor) + positiveDivisor) % positiveDivisor;
}

function greatestCommonDivisor(left: bigint, right: bigint): bigint {
  let a = left < 0n ? -left : left;
  let b = right < 0n ? -right : right;
  while (b !== 0n) {
    const remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

function evaluateBinary(
  operator: BinaryOperator,
  left: bigint,
  right: bigint,
  offset: number,
): InternalResult {
  switch (operator) {
    case "+":
      return checked(left + right, offset);
    case "-":
      return checked(left - right, offset);
    case "*":
      return checked(left * right, offset);
    case "/":
      if (right === 0n) return expressionFailure("DIVIDE_BY_ZERO", offset);
      if (left % right !== 0n) return expressionFailure("NON_INTEGRAL_DIVISION", offset);
      return checked(left / right, offset);
    case "%":
      if (right === 0n) return expressionFailure("DIVIDE_BY_ZERO", offset);
      return success(positiveModulo(left, right));
  }
}

function evaluateCall(name: string, values: bigint[], offset: number): InternalResult {
  if (name !== "mod" && name !== "quotient" && name !== "digit" && name !== "gcd" && name !== "lcm") {
    return expressionFailure("UNKNOWN_FUNCTION", offset);
  }
  if (values.length !== 2) return expressionFailure("ARITY", offset);
  const left = values[0]!;
  const right = values[1]!;

  switch (name) {
    case "mod":
      if (right === 0n) return expressionFailure("DIVIDE_BY_ZERO", offset);
      return success(positiveModulo(left, right));
    case "quotient":
      if (right === 0n) return expressionFailure("DIVIDE_BY_ZERO", offset);
      return checked(left / right, offset);
    case "digit": {
      const absolute = left < 0n ? -left : left;
      if (right < 1n || right > BigInt(absolute.toString().length)) {
        return expressionFailure("DIGIT_RANGE", offset);
      }
      const divisor = 10n ** (right - 1n);
      return success((absolute / divisor) % 10n);
    }
    case "gcd":
      return success(greatestCommonDivisor(left, right));
    case "lcm": {
      if (left === 0n || right === 0n) return success(0n);
      const gcd = greatestCommonDivisor(left, right);
      const product = (left / gcd) * right;
      return checked(product < 0n ? -product : product, offset);
    }
  }
}

function evaluateNode(node: ExpressionNode, variables: ExpressionVariables): InternalResult {
  switch (node.kind) {
    case "integer":
      return success(node.value);
    case "variable": {
      if (!Object.hasOwn(variables, node.name)) {
        return expressionFailure("UNKNOWN_IDENTIFIER", node.offset);
      }
      const value = variables[node.name];
      if (typeof value !== "number" || !Number.isSafeInteger(value)) {
        return expressionFailure("OVERFLOW", node.offset);
      }
      return success(BigInt(value));
    }
    case "unary": {
      const operand = evaluateNode(node.operand, variables);
      if (!operand.ok) return operand;
      return checked(-operand.value, node.offset);
    }
    case "binary": {
      const left = evaluateNode(node.left, variables);
      if (!left.ok) return left;
      const right = evaluateNode(node.right, variables);
      if (!right.ok) return right;
      return evaluateBinary(node.operator, left.value, right.value, node.offset);
    }
    case "call": {
      if (
        node.name !== "mod" &&
        node.name !== "quotient" &&
        node.name !== "digit" &&
        node.name !== "gcd" &&
        node.name !== "lcm"
      ) {
        return expressionFailure("UNKNOWN_FUNCTION", node.offset);
      }
      if (node.arguments.length !== 2) return expressionFailure("ARITY", node.offset);
      const values: bigint[] = [];
      for (const argument of node.arguments) {
        const value = evaluateNode(argument, variables);
        if (!value.ok) return value;
        values.push(value.value);
      }
      return evaluateCall(node.name, values, node.offset);
    }
  }
}

export function evaluateExpression(
  source: string,
  variables: ExpressionVariables = {},
): ExpressionResult {
  const tokenized = tokenizeExpression(source);
  if (!tokenized.ok) return tokenized;
  const parsed = parseExpressionTokens(tokenized.tokens);
  if (!parsed.ok) return parsed;
  const evaluated = evaluateNode(parsed.expression, variables);
  if (!evaluated.ok) return evaluated;
  return { ok: true, value: Number(evaluated.value), error_code: "", offset: -1 };
}
