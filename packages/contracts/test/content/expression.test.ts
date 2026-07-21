import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { evaluateExpression } from "../../src/index.js";

interface ExpressionFixture {
  name: string;
  source: string;
  variables: Record<string, number>;
  ok: boolean;
  value: number;
  error_code: string;
  offset: number;
}

const CASES = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/expression_cases.json", import.meta.url),
    "utf8",
  ),
) as ExpressionFixture[];

describe("safe expression engine", () => {
  it.each(CASES)("matches the shared fixture: $name", (fixture) => {
    expect(evaluateExpression(fixture.source, fixture.variables)).toEqual({
      ok: fixture.ok,
      value: fixture.value,
      error_code: fixture.error_code,
      offset: fixture.offset,
    });
  });

  it("caps UTF-16 source length before tokenization", () => {
    expect(evaluateExpression("1".repeat(513))).toEqual({
      ok: false,
      value: 0,
      error_code: "TOO_COMPLEX",
      offset: 512,
    });
    expect(evaluateExpression(`${" ".repeat(511)}😀`)).toEqual({
      ok: false,
      value: 0,
      error_code: "TOO_COMPLEX",
      offset: 512,
    });
  });

  it("rejects non-integer and unsafe variable values", () => {
    expect(evaluateExpression("A", { A: 1.5 })).toMatchObject({
      ok: false,
      error_code: "OVERFLOW",
      offset: 0,
    });
    expect(evaluateExpression("A", { A: Number.MAX_SAFE_INTEGER + 1 })).toMatchObject({
      ok: false,
      error_code: "OVERFLOW",
      offset: 0,
    });
  });

  it("does not dispatch through platform execution APIs", () => {
    const sources = [
      readFileSync(new URL("../../src/content/expression/parser.ts", import.meta.url), "utf8"),
      readFileSync(new URL("../../src/content/expression/evaluate.ts", import.meta.url), "utf8"),
    ].join("\n");

    expect(sources).not.toMatch(/\b(?:eval|Function)\s*\(/u);
    expect(sources).not.toMatch(/dynamic\s+import/iu);
  });
});
