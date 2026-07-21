import { translateLegacyExpression } from "./legacy_expression.js";
import {
  LegacyFormatError,
  type LegacyDocument,
  type LegacyField,
  type LegacyLevel,
  type LegacyQuestionToken,
  type LegacyRange,
} from "./legacy_types.js";

const MAX_SOURCE_BYTES = 256_000;
const MAX_LINES = 4_000;
const MAX_LINE_CODE_UNITS = 4_096;
const MAX_CELLS = 256;
const MAX_CELL_CODE_UNITS = 1_024;

const EXACT_FIELD_NAMES: Readonly<Record<string, string>> = {
  title: "title",
  icon: "icon",
  level: "level",
  gametype: "gametype",
  keypad: "keypad",
  description: "description",
  questiontype: "questiontype",
  "time for each quiz": "time for each quiz",
  "apples per quiz": "apples per quiz",
  "sub level increasement": "sub level increasement",
  "sub level decreasement": "sub level decreasement",
  "question number for next level": "question number for next level",
  targetnumber: "target number",
  "row of question display": "row of question display",
  "row of question display_for button": "row of question display for button",
  "question format": "question format",
  "answer equation": "answer equation",
  log1: "log1",
  log2: "log2",
  log3: "log3",
  log4: "log4",
  log5: "log5",
};

const INTEGER_FIELD_NAMES = new Set([
  "sub level increasement",
  "sub level decreasement",
  "question number for next level",
  "target number",
  "row of question display",
  "row of question display for button",
]);

const EXPRESSION_FIELD_NAMES = new Set([
  "time for each quiz",
  "apples per quiz",
  "answer equation",
]);

const PASSIVE_SINGLE_VALUE_FIELDS = new Set(["title", "icon", "description", "questiontype", "keypad"]);
const QUESTION_LITERAL_TOKENS = new Set(["_", "__", "___", "h_", "+", "-", "x", "?"]);
const LEGACY_ICON_VALUES = new Set(["plus", "minus", "multiple", "gongbaesu", "primefactorization"]);
const LEGACY_KEYPAD_VALUES = new Set(["phone3", "phone4"]);

interface ParsedRecord {
  header_parts: string[];
  cells: string[];
}

function fail(sourceName: string, line: number, column: number, message: string): never {
  throw new LegacyFormatError(sourceName, line, column, message);
}

function validateSourceText(source: string, sourceName: string): void {
  if (new TextEncoder().encode(source).length > MAX_SOURCE_BYTES) {
    fail(sourceName, 1, 1, "legacy CSV exceeds the development fixture size limit");
  }
  for (let index = 0; index < source.length; index += 1) {
    const code = source.charCodeAt(index);
    if (code === 0 || code === 0xfffd || (code < 0x20 && code !== 0x09 && code !== 0x0a && code !== 0x0d)) {
      fail(sourceName, 1, index + 1, "legacy CSV contains a forbidden control or replacement character");
    }
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = source.charCodeAt(index + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) {
        fail(sourceName, 1, index + 1, "legacy CSV contains an unpaired high surrogate");
      }
      index += 1;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      fail(sourceName, 1, index + 1, "legacy CSV contains an unpaired low surrogate");
    }
  }
}

function splitPhysicalLines(source: string, sourceName: string): string[] {
  const lines: string[] = [];
  let start = 0;
  for (let index = 0; index <= source.length; index += 1) {
    if (index !== source.length && source[index] !== "\n") continue;
    let line = source.slice(start, index);
    if (line.endsWith("\r")) line = line.slice(0, -1);
    if (line.includes("\r")) fail(sourceName, lines.length + 1, 1, "bare carriage return is not allowed");
    if (line.length > MAX_LINE_CODE_UNITS) {
      fail(sourceName, lines.length + 1, MAX_LINE_CODE_UNITS + 1, "legacy CSV line is too long");
    }
    lines.push(line);
    if (lines.length > MAX_LINES) fail(sourceName, lines.length, 1, "legacy CSV has too many lines");
    start = index + 1;
  }
  return lines;
}

function splitHeaderParts(header: string, sourceName: string, line: number): string[] {
  const parts: string[] = [];
  let start = 0;
  for (let index = 0; index <= header.length; index += 1) {
    if (index !== header.length && header[index] !== ",") continue;
    const part = header.slice(start, index).trim();
    if (part.length === 0) fail(sourceName, line, start + 2, "empty legacy header segment");
    parts.push(part);
    start = index + 1;
  }
  return parts;
}

function parseCells(source: string, sourceName: string, line: number, columnOffset: number): string[] {
  const cells: string[] = [];
  let value = "";
  let state: "start" | "unquoted" | "quoted" | "after_quote" = "start";

  const finish = () => {
    const cell = state === "quoted" || state === "after_quote" ? value : value.trim();
    if (cell.length === 0) fail(sourceName, line, columnOffset, "empty legacy CSV cell");
    if (cell.length > MAX_CELL_CODE_UNITS) fail(sourceName, line, columnOffset, "legacy CSV cell is too long");
    cells.push(cell);
    if (cells.length > MAX_CELLS) fail(sourceName, line, columnOffset, "legacy CSV has too many cells");
    value = "";
    state = "start";
  };

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index] ?? "";
    if (state === "start") {
      if (character === '"') state = "quoted";
      else if (character === ",") finish();
      else {
        value += character;
        state = "unquoted";
      }
      continue;
    }
    if (state === "unquoted") {
      if (character === ",") finish();
      else if (character === '"') fail(sourceName, line, columnOffset + index, "quote inside an unquoted cell");
      else value += character;
      continue;
    }
    if (state === "quoted") {
      if (character !== '"') {
        value += character;
      } else if (source[index + 1] === '"') {
        value += '"';
        index += 1;
      } else {
        state = "after_quote";
      }
      continue;
    }
    if (character === ",") finish();
    else if (character !== " " && character !== "\t") {
      fail(sourceName, line, columnOffset + index, "unexpected text after a quoted cell");
    }
  }
  if (state === "quoted") fail(sourceName, line, columnOffset + source.length, "unclosed quoted cell");
  finish();
  return cells;
}

function parseRecord(rawLine: string, sourceName: string, line: number): ParsedRecord {
  if (!rawLine.startsWith("[")) fail(sourceName, line, 1, "legacy record must begin with a bracketed field");
  let close = -1;
  for (let index = 1; index < rawLine.length; index += 1) {
    const character = rawLine[index] ?? "";
    if (character === "[") fail(sourceName, line, index + 1, "nested legacy field bracket");
    if (character === "]") {
      close = index;
      break;
    }
  }
  if (close === -1) fail(sourceName, line, rawLine.length, "unclosed legacy field bracket");
  if (rawLine[close + 1] !== ",") fail(sourceName, line, close + 2, "legacy field must be followed by a comma");
  return {
    header_parts: splitHeaderParts(rawLine.slice(1, close), sourceName, line),
    cells: parseCells(rawLine.slice(close + 2), sourceName, line, close + 3),
  };
}

function parseIntegerAtLeast(
  source: string,
  sourceName: string,
  line: number,
  label: string,
  minimum: number,
): number {
  if (source.length === 0) fail(sourceName, line, 1, `${label} is empty`);
  let value = 0;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index] ?? "";
    if (character < "0" || character > "9") fail(sourceName, line, index + 1, `${label} must be an integer`);
    value = value * 10 + Number(character);
    if (!Number.isSafeInteger(value)) fail(sourceName, line, index + 1, `${label} is unsafe`);
  }
  if (value < minimum) {
    fail(sourceName, line, 1, minimum === 0 ? `${label} must be nonnegative` : `${label} must be positive`);
  }
  return value;
}

function parsePositiveInteger(source: string, sourceName: string, line: number, label: string): number {
  return parseIntegerAtLeast(source, sourceName, line, label, 1);
}

function canonicalFieldName(rawName: string, sourceName: string, line: number): string {
  const normalized = rawName.toLowerCase();
  const exact = EXACT_FIELD_NAMES[normalized];
  if (exact !== undefined) return exact;
  if (normalized.startsWith("component ")) {
    const suffix = rawName.slice("component ".length).trim();
    if (suffix.length === 1 && suffix >= "A" && suffix <= "Z") return `component ${suffix}`;
  }
  fail(sourceName, line, 2, `unsupported legacy field ${rawName}`);
}

function parseRange(parts: string[], sourceName: string, line: number): LegacyRange | null {
  if (parts.length === 1) return null;
  if (parts.length !== 3) fail(sourceName, line, 2, "legacy range requires exactly minimum and maximum");
  const minimum = parsePositiveInteger(parts[1]!, sourceName, line, "range minimum");
  const maximum = parsePositiveInteger(parts[2]!, sourceName, line, "range maximum");
  if (minimum > maximum) fail(sourceName, line, 2, "legacy range minimum exceeds maximum");
  return { minimum, maximum };
}

function parseIntegerCells(cells: string[], sourceName: string, line: number, label: string): number[] {
  return cells.map((cell) => parseIntegerAtLeast(cell, sourceName, line, label, 0));
}

function assertPassiveCell(cell: string, sourceName: string, line: number): void {
  const lowercase = cell.toLowerCase();
  const forbiddenCharacter = [...cell].some(
    (character) =>
      character === ";" ||
      character === "`" ||
      character === "{" ||
      character === "}" ||
      character === "<" ||
      character === ">" ||
      character === "\\" ||
      character === "$",
  );
  if (
    forbiddenCharacter ||
    lowercase.includes("javascript:") ||
    lowercase.includes("script:") ||
    lowercase.includes("://") ||
    lowercase.includes("../") ||
    lowercase.includes("=>")
  ) {
    fail(sourceName, line, 1, "passive legacy cell contains executable or path syntax");
  }
}

export function parseLegacyQuestionFormat(
  source: string,
  sourceName = "legacy-question-format",
  line = 1,
): LegacyQuestionToken[] {
  const tokens: LegacyQuestionToken[] = [];
  let index = 0;
  while (index < source.length) {
    if (source[index] !== "[") fail(sourceName, line, index + 1, "question format contains text outside a token");
    const start = index;
    index += 1;
    while (index < source.length && source[index] !== "]") {
      if (source[index] === "[") fail(sourceName, line, index + 1, "nested question-format token");
      index += 1;
    }
    if (index >= source.length) fail(sourceName, line, start + 1, "unclosed question-format token");
    const rawToken = source.slice(start + 1, index);
    index += 1;

    if (QUESTION_LITERAL_TOKENS.has(rawToken)) {
      tokens.push({ kind: "literal", value: rawToken });
      continue;
    }

    let component = "";
    let qualifier: string | null = null;
    if (rawToken.startsWith("component ")) {
      component = rawToken.slice("component ".length);
    } else if (rawToken.startsWith("component#")) {
      const rest = rawToken.slice("component#".length);
      const separator = rest.indexOf(" ");
      if (separator === -1) fail(sourceName, line, start + 2, "malformed qualified component token");
      qualifier = rest.slice(0, separator);
      component = rest.slice(separator + 1);
      if (qualifier !== "1" && qualifier !== "?") {
        fail(sourceName, line, start + 2, "unsupported component qualifier");
      }
    } else {
      fail(sourceName, line, start + 2, `unsupported question-format token ${rawToken}`);
    }
    if (!(component.length === 1 && component >= "A" && component <= "Z")) {
      fail(sourceName, line, start + 2, "component token must name one uppercase component");
    }
    tokens.push({ kind: "component", component, qualifier });
  }
  if (tokens.length === 0) fail(sourceName, line, 1, "question format cannot be empty");
  return tokens;
}

function buildField(
  key: string,
  range: LegacyRange | null,
  cells: string[],
  sourceName: string,
  line: number,
): LegacyField {
  let integerValues: number[] | null = null;
  let computed = false;
  let canonicalExpression: string | null = null;
  let questionTokens: LegacyQuestionToken[] | null = null;

  if (key.startsWith("component ")) {
    if (cells.length === 1 && cells[0]!.startsWith("(answer)")) {
      computed = true;
      try {
        canonicalExpression = translateLegacyExpression(cells[0]!);
      } catch (error) {
        fail(sourceName, line, 1, error instanceof Error ? error.message : "invalid computed component");
      }
    } else {
      integerValues = parseIntegerCells(cells, sourceName, line, key);
    }
  } else if (EXPRESSION_FIELD_NAMES.has(key)) {
    if (cells.length !== 1) fail(sourceName, line, 1, `${key} requires one expression cell`);
    try {
      canonicalExpression = translateLegacyExpression(cells[0]!);
    } catch (error) {
      fail(sourceName, line, 1, error instanceof Error ? error.message : `invalid ${key}`);
    }
  } else if (INTEGER_FIELD_NAMES.has(key)) {
    integerValues = parseIntegerCells(cells, sourceName, line, key);
  } else if (key === "question format") {
    if (cells.length !== 1) fail(sourceName, line, 1, "question format requires one cell");
    questionTokens = parseLegacyQuestionFormat(cells[0]!, sourceName, line);
  } else if (key === "gametype") {
    for (const cell of cells) {
      if (cell !== "+" && cell !== "-" && cell !== "x" && cell !== "/") {
        fail(sourceName, line, 1, "unsupported legacy game type");
      }
    }
  } else {
    if (PASSIVE_SINGLE_VALUE_FIELDS.has(key) && cells.length !== 1) {
      fail(sourceName, line, 1, `${key} requires one cell`);
    }
    for (const cell of cells) assertPassiveCell(cell, sourceName, line);
    if (key === "icon" && !LEGACY_ICON_VALUES.has(cells[0]!)) {
      fail(sourceName, line, 1, "unsupported legacy icon identifier");
    }
    if (key === "keypad" && !LEGACY_KEYPAD_VALUES.has(cells[0]!)) {
      fail(sourceName, line, 1, "unsupported legacy keypad identifier");
    }
    if (key === "questiontype" && cells[0] !== "game1") {
      fail(sourceName, line, 1, "unsupported legacy question type");
    }
  }

  return {
    key,
    range,
    cells,
    integer_values: integerValues,
    computed,
    canonical_expression: canonicalExpression,
    question_tokens: questionTokens,
    line,
  };
}

function rangesOverlap(left: LegacyRange, right: LegacyRange): boolean {
  return left.minimum <= right.maximum && right.minimum <= left.maximum;
}

function assertUnambiguousField(fields: LegacyField[], candidate: LegacyField, sourceName: string): void {
  for (const existing of fields) {
    if (existing.key !== candidate.key) continue;
    if (existing.range === null || candidate.range === null) {
      fail(sourceName, candidate.line, 1, `duplicate unscoped legacy field ${candidate.key}`);
    }
    if (rangesOverlap(existing.range, candidate.range)) {
      fail(sourceName, candidate.line, 1, `overlapping legacy ranges for ${candidate.key}`);
    }
  }
}

export function parseLegacyCsv(rawSource: string, sourceName: string): LegacyDocument {
  if (typeof rawSource !== "string") throw new TypeError("Legacy CSV source must be text");
  if (typeof sourceName !== "string" || sourceName.length === 0) {
    throw new TypeError("Legacy CSV source name must be nonempty");
  }
  validateSourceText(rawSource, sourceName);
  const source = rawSource.startsWith("\ufeff") ? rawSource.slice(1) : rawSource;
  if (source.includes("\ufeff")) fail(sourceName, 1, 1, "UTF-8 BOM is allowed only at the beginning");

  const metadata: LegacyField[] = [];
  const levels: LegacyLevel[] = [];
  const levelNumbers = new Set<number>();
  let currentLevel: LegacyLevel | null = null;

  const lines = splitPhysicalLines(source, sourceName);
  for (let index = 0; index < lines.length; index += 1) {
    const rawLine = lines[index]!;
    const line = index + 1;
    if (rawLine.trim().length === 0) continue;
    const record = parseRecord(rawLine, sourceName, line);
    const key = canonicalFieldName(record.header_parts[0]!, sourceName, line);
    const range = parseRange(record.header_parts, sourceName, line);

    if (key === "level") {
      if (range !== null) fail(sourceName, line, 1, "level marker cannot have a range");
      if (record.cells.length !== 1) fail(sourceName, line, 1, "level marker requires one integer");
      const level = parsePositiveInteger(record.cells[0]!, sourceName, line, "level");
      if (levelNumbers.has(level)) fail(sourceName, line, 1, `duplicate legacy level ${level}`);
      levelNumbers.add(level);
      currentLevel = { level, fields: [], line };
      levels.push(currentLevel);
      continue;
    }

    if (key === "title" || key === "icon") {
      if (currentLevel !== null) fail(sourceName, line, 1, `${key} must appear before the first level`);
      if (range !== null) fail(sourceName, line, 1, `${key} cannot have a range`);
      const candidate = buildField(key, range, record.cells, sourceName, line);
      assertUnambiguousField(metadata, candidate, sourceName);
      metadata.push(candidate);
      continue;
    }

    if (currentLevel === null) fail(sourceName, line, 1, `${key} appears before a level marker`);
    const candidate = buildField(key, range, record.cells, sourceName, line);
    assertUnambiguousField(currentLevel.fields, candidate, sourceName);
    currentLevel.fields.push(candidate);
  }

  for (const required of ["title", "icon"]) {
    if (!metadata.some((entry) => entry.key === required)) fail(sourceName, 1, 1, `missing ${required} metadata`);
  }
  if (levels.length === 0) fail(sourceName, 1, 1, "legacy CSV contains no level");
  return { source_name: sourceName, metadata, levels };
}
