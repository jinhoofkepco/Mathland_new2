import { describe, expect, it } from "vitest";

import { diffDraft } from "./draft_diff";

describe("diffDraft", () => {
  it("returns stable JSON pointer changes without mutating either input", () => {
    const before = { a: 1, b: { x: 2 }, list: [1, 2] };
    const after = { a: 1, b: { x: 3 }, c: true, list: [1] };
    expect(diffDraft(before, after)).toEqual([
      { kind: "changed", path: "/b/x", before: 2, after: 3 },
      { kind: "added", path: "/c", before: undefined, after: true },
      { kind: "removed", path: "/list/1", before: 2, after: undefined },
    ]);
    expect(before).toEqual({ a: 1, b: { x: 2 }, list: [1, 2] });
  });
});
