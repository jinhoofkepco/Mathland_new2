import { describe, expect, it } from "vitest";

import { applyJsonPatch } from "./ai_patch";

describe("applyJsonPatch", () => {
  it("applies a detached RFC 6902 subset without mutating the source", () => {
    const source = { run: { target: 10 }, bands: ["intro", "practice"] };
    const result = applyJsonPatch(source, [
      { op: "test", path: "/run/target", value: 10 },
      { op: "replace", path: "/run/target", value: 14 },
      { op: "add", path: "/bands/-", value: "challenge" },
    ]);

    expect(result).toEqual({ run: { target: 14 }, bands: ["intro", "practice", "challenge"] });
    expect(source).toEqual({ run: { target: 10 }, bands: ["intro", "practice"] });
  });

  it("rejects invalid paths and failed test operations", () => {
    expect(() => applyJsonPatch({ value: 1 }, [
      { op: "replace", path: "/missing", value: 2 },
    ])).toThrow(/does not exist/i);
    expect(() => applyJsonPatch({ value: 1 }, [
      { op: "test", path: "/value", value: 2 },
    ])).toThrow(/test operation failed/i);
    expect(() => applyJsonPatch({ value: 1 }, [
      { op: "add", path: "/__proto__/polluted", value: true },
    ])).toThrow(/reserved/i);
  });
});
