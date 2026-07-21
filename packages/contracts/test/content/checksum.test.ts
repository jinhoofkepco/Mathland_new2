import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  CanonicalJsonError,
  ContentJsonParseError,
  canonicalJson,
  contentChecksum,
  parseJsonStrict,
} from "../../src/index.js";

interface NumberVector {
  bits: string;
  canonical: string;
}

interface StringVectorFixture {
  c0: {
    codepoint: number;
    value_canonical: string;
    key_canonical: string;
  }[];
  unicode_corpus: {
    start_codepoint: number;
    codepoint_count: number;
    object_checksum: string;
  };
}

const NUMBER_VECTORS = JSON.parse(
  readFileSync(
    new URL("../../../../tests/fixtures/contracts/ecmascript_number_vectors.json", import.meta.url),
    "utf8",
  ),
) as NumberVector[];

const STRING_VECTORS = JSON.parse(
  readFileSync(
    new URL("../../../../tests/fixtures/contracts/ecmascript_string_vectors.json", import.meta.url),
    "utf8",
  ),
) as StringVectorFixture;

const PUBLISHED_PACKAGE = JSON.parse(
  readFileSync(
    new URL("../../../../tests/content/fixtures/minimal_valid_activity.json", import.meta.url),
    "utf8",
  ),
) as Record<string, unknown>;

function numberFromBits(bits: string): number {
  const bytes = new ArrayBuffer(8);
  const view = new DataView(bytes);
  view.setBigUint64(0, BigInt(`0x${bits}`));
  return view.getFloat64(0);
}

describe("canonical JSON", () => {
  it("matches ECMAScript escaping for every C0 control in values and keys", () => {
    expect(STRING_VECTORS.c0).toHaveLength(0x20);
    for (const vector of STRING_VECTORS.c0) {
      const character = String.fromCharCode(vector.codepoint);
      const value = { value: character };
      const keyed = { [`k${character}`]: 1 };

      expect(JSON.stringify(value), `value U+${vector.codepoint.toString(16).padStart(4, "0")}`).toBe(
        vector.value_canonical,
      );
      expect(canonicalJson(value)).toBe(vector.value_canonical);
      expect(JSON.stringify(keyed), `key U+${vector.codepoint.toString(16).padStart(4, "0")}`).toBe(
        vector.key_canonical,
      );
      expect(canonicalJson(keyed)).toBe(vector.key_canonical);
    }
  });

  it("matches ECMAScript across a 4,096-codepoint Unicode corpus", () => {
    const { start_codepoint: start, codepoint_count: count, object_checksum: checksum } =
      STRING_VECTORS.unicode_corpus;
    const corpus = Array.from({ length: count }, (_, index) =>
      String.fromCodePoint(start + index),
    ).join("");
    const value = { value: corpus };

    expect([...corpus]).toHaveLength(4_096);
    expect(canonicalJson(value)).toBe(JSON.stringify(value));
    expect(contentChecksum(value)).toBe(checksum);
  });

  it("preserves the published package checksum fixture", () => {
    expect(contentChecksum(PUBLISHED_PACKAGE)).toBe(PUBLISHED_PACKAGE.checksum);
  });

  it("uses the exact ECMAScript shortest representation for IEEE-754 doubles", () => {
    const value = numberFromBits("3b1d8e556da8dd77");

    expect(canonicalJson({ n: value })).toBe('{"n":6.1120356918828906e-24}');
    expect(contentChecksum({ n: value })).toBe(
      "sha256:499f3763d3ce3f8b86565421bd9d3c1948bac88f3332d4ebb7439fb8bd14de2b",
    );
  });

  it("matches the ECMAScript representation across a deterministic IEEE-754 corpus", () => {
    expect(NUMBER_VECTORS).toHaveLength(128);
    for (const vector of NUMBER_VECTORS) {
      expect(canonicalJson(numberFromBits(vector.bits)), vector.bits).toBe(vector.canonical);
    }
  });

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

  it("sorts object keys by UTF-16 code units rather than Unicode scalar values", () => {
    const astral = "𐀀";
    const privateUseBmp = "";

    expect(canonicalJson({ [privateUseBmp]: 2, [astral]: 1 })).toBe(
      `{"${astral}":1,"${privateUseBmp}":2}`,
    );
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

  it("rejects lone UTF-16 surrogates in string values and object keys", () => {
    const loneHigh = String.fromCharCode(0xd800);
    const loneLow = String.fromCharCode(0xdc00);

    expect(() => canonicalJson({ value: loneHigh })).toThrowError(
      expect.objectContaining({ code: "LONE_SURROGATE", path: ["value"] }),
    );
    expect(() => canonicalJson({ [loneLow]: 1 })).toThrowError(
      expect.objectContaining({ code: "LONE_SURROGATE", path: [loneLow] }),
    );
    expect(canonicalJson({ value: "😀" })).toBe('{"value":"😀"}');
  });

  it("rejects U+FFFD in string values and object keys", () => {
    const replacement = "\ufffd";

    expect(() => canonicalJson({ value: replacement })).toThrowError(
      expect.objectContaining({ code: "INVALID_UNICODE", path: ["value"] }),
    );
    expect(() => canonicalJson({ [replacement]: 1 })).toThrowError(
      expect.objectContaining({ code: "INVALID_UNICODE", path: [replacement] }),
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

  it("counts source length as UTF-16 code units and caps nesting at 64", () => {
    const exactlyAtLimit = `"${"😀".repeat(999_999)}"`;
    const overLimit = `"${"😀".repeat(1_000_000)}"`;

    expect(exactlyAtLimit.length).toBe(2_000_000);
    expect(parseJsonStrict(exactlyAtLimit)).toBe("😀".repeat(999_999));
    expect(() => parseJsonStrict(overLimit)).toThrowError(
      expect.objectContaining({ code: "SOURCE_TOO_LARGE" }),
    );
    expect(parseJsonStrict(`${"[".repeat(64)}0${"]".repeat(64)}`)).toBeDefined();
    expect(() => parseJsonStrict(`${"[".repeat(65)}0${"]".repeat(65)}`)).toThrowError(
      expect.objectContaining({ code: "NESTING_TOO_DEEP" }),
    );
  });

  it("rejects escaped and literal lone surrogates in JSON strings and keys", () => {
    const loneHigh = String.fromCharCode(0xd800);

    for (const source of [
      '"\\ud800"',
      '"\\udc00"',
      '{"\\ud800":1}',
      `"${loneHigh}"`,
      `{"${loneHigh}":1}`,
    ]) {
      expect(() => parseJsonStrict(source)).toThrowError(
        expect.objectContaining({ code: "INVALID_JSON" }),
      );
    }
    expect(parseJsonStrict('"\\ud83d\\ude00"')).toBe("😀");
  });

  it("rejects escaped and literal U+FFFD before JSON decoding", () => {
    for (const source of ['"\ufffd"', '"\\ufffd"', '{"\ufffd":1}', '{"\\ufffd":1}']) {
      expect(() => parseJsonStrict(source)).toThrowError(
        expect.objectContaining({ code: "INVALID_JSON" }),
      );
    }
  });
});
