import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { GeneratorRegistry, evaluateExpression, validateActivityDraft } from "../../src/index.js";
import {
  convertLegacyCsv,
  convertLegacyCsvWithEvidence,
} from "../../../../tools/content/legacy/convert_legacy.js";
import { translateLegacyExpression } from "../../../../tools/content/legacy/legacy_expression.js";
import { parseLegacyCsv } from "../../../../tools/content/legacy/parse_legacy_csv.js";

const FIXTURE_ROOT = new URL("../../../../tools/content/fixtures/legacy/", import.meta.url);
const FIXTURE_NAMES = [
  "quiz_game_11.csv",
  "quiz_game_7.csv",
  "quiz_game_4.csv",
  "quiz_game_9.csv",
  "quiz_game_8_1.csv",
] as const;

const FIXTURE_SHA256 = {
  "quiz_game_11.csv": "2bc0680a92758d1038854574f7f1f0dafe8ea17f5504990bd91e39b54de08329",
  "quiz_game_7.csv": "332afe72a2ede14f8cbc7e6659ca5028bafac368567b9550afb2a884041f1308",
  "quiz_game_4.csv": "c6988f44a219ae324fc7d532ab8aafe1d360ee834888e945bfec07b2a4cbdc8c",
  "quiz_game_9.csv": "d5e83eca772cfd3c6657702e3432fb7e807e46b29ddc198b201988938671bdc4",
  "quiz_game_8_1.csv": "b5fbfd500cc7b309bc9ddd15700714135d41693505adc93e4e20c0412b8e1a2b",
} as const;

const PASSIVE_TEXT_FIELDS = ["title", "description", "log1"] as const;
const PASSIVE_TEXT_ATTACKS = [
  "process.exit(1)",
  "require(child_process)",
  "ok&&sh",
  "ok|sh",
  "/etc/passwd",
  "C:/secret",
  "//server/share",
  "file:/etc/passwd",
  "..%2fsecret",
  ".. /secret",
  "%252e%252e%252fsecret",
  "file%3a%2fetc%2fpasswd",
  "process．exit（1）",
  "．．／secret",
  "＼＼server＼share",
] as const;

interface ExpectedConversionFile {
  source_commit: string;
  expression_parity_cases: {
    legacy: string;
    canonical: string;
    variables: Record<string, number>;
    expected: number;
  }[];
  sources: Record<string, ReturnType<typeof convertLegacyCsvWithEvidence>>;
}

function field(document: ReturnType<typeof parseLegacyCsv>, key: string, index = 0) {
  const matches = document.levels[0]!.fields.filter((candidate) => candidate.key === key);
  expect(matches.length).toBeGreaterThan(index);
  return matches[index]!;
}

function sourceWithPassiveText(
  fieldName: (typeof PASSIVE_TEXT_FIELDS)[number],
  value: string,
): string {
  if (fieldName === "title") {
    return [`[title],${value}`, "[icon],plus", "[level],1"].join("\n");
  }
  return ["[title],x", "[icon],plus", "[level],1", `[${fieldName}],${value}`].join(
    "\n",
  );
}

describe("legacy expression translation", () => {
  it.each([
    ["Mod[A+E~10]", "mod(A+E,10)"],
    ["Quotient[X~Y]", "quotient(X,Y)"],
    ["digit[answer~3]", "digit(answer,3)"],
    ["gcd[X~Y]", "gcd(X,Y)"],
    ["lcm[lcm[X~Y]~Z]", "lcm(lcm(X,Y),Z)"],
    ["65-Quotient[(sub_level)~8]", "65-quotient(sub_level,8)"],
    ["(answer)Mod[A+E~10]", "mod(A+E,10)"],
  ])("translates %s without evaluating it", (legacy, canonical) => {
    expect(translateLegacyExpression(legacy)).toBe(canonical);
  });

  it.each([
    "Pow[A~2]",
    "Mod[A~10",
    "A;process.exit(1)",
    "globalThis.fetch",
    "A+`command`",
    "A+$(command)",
    "Mod[A~10] trailing",
    "(answer)(answer)A",
  ])("rejects unsupported, unbalanced, or executable syntax: %s", (source) => {
    expect(() => translateLegacyExpression(source)).toThrow();
  });
});

describe("legacy CSV state-machine parser", () => {
  it("parses a BOM, levels, ranged repeats, components, computed values, and question tokens", () => {
    const source = [
      "\ufeff[title],테스트[enter]게임",
      "[icon],plus",
      "",
      "[level],1",
      "[component A,1,10],1,2,3",
      "[component A,11,20],4,5,6",
      "[component B],(answer)Mod[A+1~10]",
      "[time for each quiz],20-Quotient[(sub_level)~8]",
      "[question format],[_][component A][+][component#1 B][component#? C][?]",
      "[answer equation],Mod[A+B~10]",
    ].join("\r\n");

    const document = parseLegacyCsv(source, "inline.csv");
    expect(document.source_name).toBe("inline.csv");
    expect(document.metadata.map((entry) => entry.key)).toEqual(["title", "icon"]);
    expect(document.levels.map((entry) => entry.level)).toEqual([1]);

    const firstRange = field(document, "component A", 0);
    const secondRange = field(document, "component A", 1);
    expect(firstRange.range).toEqual({ minimum: 1, maximum: 10 });
    expect(secondRange.range).toEqual({ minimum: 11, maximum: 20 });
    expect(firstRange.integer_values).toEqual([1, 2, 3]);
    expect(secondRange.integer_values).toEqual([4, 5, 6]);

    const computed = field(document, "component B");
    expect(computed.computed).toBe(true);
    expect(computed.canonical_expression).toBe("mod(A+1,10)");
    expect(field(document, "time for each quiz").canonical_expression).toBe(
      "20-quotient(sub_level,8)",
    );
    expect(field(document, "answer equation").canonical_expression).toBe("mod(A+B,10)");

    const tokens = field(document, "question format").question_tokens ?? [];
    expect(
      tokens.map((token) =>
        token.kind === "component"
          ? `${token.component}${token.qualifier === null ? "" : `:${token.qualifier}`}`
          : token.value,
      ),
    ).toEqual(["_", "A", "+", "B:1", "C:?", "?"]);
  });

  it("accepts only the reviewed display-text and legacy-log grammar", () => {
    const source = [
      "[title],테스트[enter]게임 -New 1-!!~~~+",
      "[icon],plus",
      "[level],1",
      "[description],2자리수 빼기!!",
      "[log1],1의자리::A+E=Mod[A+E~10]=digit[answer~5]",
      "[log2],A B * C D=(10*A+B)*(10*C+D)=answer",
    ].join("\n");

    const document = parseLegacyCsv(source, "reviewed-text.csv");
    expect(document.metadata[0]!.cells).toEqual(["테스트[enter]게임 -New 1-!!~~~+"]);
    expect(field(document, "description").cells).toEqual(["2자리수 빼기!!"]);
    expect(field(document, "log1").cells).toEqual([
      "1의자리::A+E=Mod[A+E~10]=digit[answer~5]",
    ]);
  });

  it.each(
    PASSIVE_TEXT_FIELDS.flatMap((fieldName) =>
      PASSIVE_TEXT_ATTACKS.map((value) => [fieldName, value] as const),
    ),
  )("rejects executable or path syntax in %s: %s", (fieldName, value) => {
    expect(() => parseLegacyCsv(sourceWithPassiveText(fieldName, value), "bad.csv")).toThrow();
  });

  it.each([
    "[title],x\n[icon],plus\n[level],1\n[component A,10,1],1",
    "[title],x\n[icon],plus\n[level],1\n[component A,1],1",
    "[title],x\n[icon],plus\n[level],1\n[component A,one,2],1",
    "[title],x\n[icon],plus\n[level],1\n[component A,1,10,1",
    "[title],x\n[icon],plus\n[level],1\n[component A,1,10],1\n[component A,10,20],2",
    "[title],x\n[icon],plus\n[level],1\n[level],1",
    "[title],x\n[icon],plus\n[level],1\n[answer equation],A;quit()",
    "[title],x\n[icon],plus\n[level],1\n[question format],[component A][script:quit]",
    "[title],<script>alert(1)</script>\n[icon],plus\n[level],1",
    "[title],x\n[icon],../../escape\n[level],1",
    "[title],x\n[icon],plus\n[level],1\n[description],javascript:alert(1)",
    "[title],x\n[icon],plus\n[level],1\n[log1],ok;system()",
  ])("fails closed on malformed or ambiguous source", (source) => {
    expect(() => parseLegacyCsv(source, "bad.csv")).toThrow();
  });
});

describe("pinned legacy fixture conversion", () => {
  const expected = JSON.parse(
    readFileSync(new URL("expected_conversion.json", FIXTURE_ROOT), "utf8"),
  ) as ExpectedConversionFile;

  it("pins the exact upstream commit and byte hashes", () => {
    expect(expected.source_commit).toBe("08b9e7589a335f0c5674cfac6743132f8c4870f2");
    for (const fixtureName of FIXTURE_NAMES) {
      const bytes = readFileSync(new URL(fixtureName, FIXTURE_ROOT));
      expect(createHash("sha256").update(bytes).digest("hex"), fixtureName).toBe(
        FIXTURE_SHA256[fixtureName],
      );
    }
  });

  it("keeps development-only CSV fixtures outside Godot's resource importer", () => {
    expect(readFileSync(new URL(".gdignore", FIXTURE_ROOT), "utf8")).toBe(
      "# Development-only legacy fixtures; do not import CSV files as Godot translations.\n",
    );
  });

  it.each(FIXTURE_NAMES)("matches the reviewed conversion for %s", (fixtureName) => {
    const source = readFileSync(new URL(fixtureName, FIXTURE_ROOT), "utf8");
    const actual = convertLegacyCsvWithEvidence(source, fixtureName);
    expect(actual).toEqual(expected.sources[fixtureName]);
    expect(convertLegacyCsv(source, fixtureName)).toEqual(actual.draft);
    const report = validateActivityDraft(actual.draft);
    expect(report.valid).toBe(true);
    expect(report.issues).toEqual([]);
    expect(report.samples).toHaveLength(12);

    for (const band of actual.draft.difficulty_bands) {
      const generator = new GeneratorRegistry().create(band.generator_id);
      expect(generator).not.toBeNull();
      expect(generator!.validateParameters(band.generator_parameters)).toEqual({
        valid: true,
        issues: [],
      });
    }

    const runtimeJson = JSON.stringify(actual.draft);
    expect(runtimeJson).not.toContain("Mod[");
    expect(runtimeJson).not.toContain("Quotient[");
    expect(runtimeJson).not.toContain("(answer)");
    expect(runtimeJson).not.toContain("answer equation");
    expect(runtimeJson).not.toContain("question format");
  });

  it("keeps translated equations only in development compatibility evidence", () => {
    for (const conversion of Object.values(expected.sources)) {
      expect(conversion.compatibility_assertions.length).toBeGreaterThan(0);
      for (const assertion of conversion.compatibility_assertions) {
        expect(assertion.canonical_expression).not.toContain("[");
        expect(assertion.canonical_expression).not.toContain("~");
      }
    }
  });

  it("keeps TypeScript translation and canonical integer evaluation in parity", () => {
    for (const fixture of expected.expression_parity_cases) {
      expect(translateLegacyExpression(fixture.legacy)).toBe(fixture.canonical);
      expect(evaluateExpression(fixture.canonical, fixture.variables)).toEqual({
        ok: true,
        value: fixture.expected,
        error_code: "",
        offset: -1,
      });
    }
  });

  it.each(["../quiz_game_11.csv", "quiz_game_11.CSV", "unknown.csv"])(
    "rejects an unpinned source identity: %s",
    (sourceName) => {
      const source = readFileSync(new URL("quiz_game_11.csv", FIXTURE_ROOT), "utf8");
      expect(() => convertLegacyCsv(source, sourceName)).toThrow();
    },
  );
});
