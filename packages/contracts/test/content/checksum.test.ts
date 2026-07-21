import { describe, expect, it } from "vitest";

import {
  CanonicalJsonError,
  ContentJsonParseError,
  canonicalJson,
  contentChecksum,
  parseJsonStrict,
} from "../../src/index.js";

describe("canonical JSON", () => {
  it("sorts object keys recursively, preserves arrays, and omits only requested top-level keys", () => {
    const a = {
      schema_version: 1,
      content_version: "1.0.0",
      activity_id: "addition_ones",
      z: [2, 1],
      nested: { y: 2, checksum: "keep", x: 1 },
      checksum: "ignored",
    };
    const b = {
      nested: { x: 1, checksum: "keep", y: 2 },
      activity_id: "addition_ones",
      content_version: "1.0.0",
      schema_version: 1,
      z: [2, 1],
    };

    expect(canonicalJson(a, { omitTopLevel: ["checksum"] })).toBe(canonicalJson(b));
    expect(canonicalJson(a, { omitTopLevel: ["checksum"] })).toBe(
      '{"activity_id":"addition_ones","content_version":"1.0.0","nested":{"checksum":"keep","x":1,"y":2},"schema_version":1,"z":[2,1]}',
    );
    expect(canonicalJson({ z: [1, 2] })).not.toBe(canonicalJson({ z: [2, 1] }));
  });

  it("creates stable lowercase UTF-8 SHA-256 checksums without mutating input", () => {
    const value = { title: "수학 섬", a: { y: 2, x: 1 }, checksum: "old" };
    const snapshot = structuredClone(value);

    const checksum = contentChecksum(value);

    expect(checksum).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(checksum).toBe(
      contentChecksum({ a: { x: 1, y: 2 }, checksum: "different", title: "수학 섬" }),
    );
    expect(value).toEqual(snapshot);
  });

  it.each([
    ["undefined", { value: undefined }],
    ["function", { value: () => 1 }],
    ["symbol", { value: Symbol("unsafe") }],
    ["non-finite", { value: Number.POSITIVE_INFINITY }],
    ["unsafe integer", { value: Number.MAX_SAFE_INTEGER + 1 }],
    ["bigint", { value: 1n }],
    ["sparse array", { value: new Array(1) }],
  ])("rejects %s values instead of silently changing them", (_label, value) => {
    expect(() => canonicalJson(value)).toThrow(CanonicalJsonError);
  });

  it("rejects cycles and non-JSON object instances", () => {
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;

    expect(() => canonicalJson(cyclic)).toThrowError(expect.objectContaining({ code: "CYCLE" }));
    expect(() => canonicalJson({ value: new Date() })).toThrowError(
      expect.objectContaining({ code: "NON_PLAIN_OBJECT" }),
    );
  });
});

describe("strict raw JSON boundary", () => {
  it("rejects duplicate keys including escaped aliases before JSON.parse can erase them", () => {
    const duplicate = '{"activity_id":"addition_ones","nested":{"seed":1,"s\\u0065ed":7}}';

    expect(() => parseJsonStrict(duplicate)).toThrowError(
      expect.objectContaining({
        name: "ContentJsonParseError",
        code: "DUPLICATE_KEY",
        path: ["nested", "seed"],
      }),
    );
  });

  it("parses valid JSON and reports malformed input through a stable error type", () => {
    expect(parseJsonStrict('{"a":[true,null,-1.25e2],"한글":"값"}')).toEqual({
      a: [true, null, -125],
      한글: "값",
    });
    expect(() => parseJsonStrict('{"a":01}')).toThrow(ContentJsonParseError);
  });
});
