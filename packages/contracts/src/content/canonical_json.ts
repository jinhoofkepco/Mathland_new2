export type JsonPath = readonly (string | number)[];

export type CanonicalJsonErrorCode =
  | "UNSUPPORTED_TYPE"
  | "NON_FINITE_NUMBER"
  | "UNSAFE_INTEGER"
  | "SPARSE_ARRAY"
  | "NON_PLAIN_OBJECT"
  | "ACCESSOR_PROPERTY"
  | "SYMBOL_KEY"
  | "LONE_SURROGATE"
  | "CYCLE";

export class CanonicalJsonError extends TypeError {
  readonly code: CanonicalJsonErrorCode;
  readonly path: JsonPath;

  constructor(code: CanonicalJsonErrorCode, path: JsonPath, message: string) {
    super(message);
    this.name = "CanonicalJsonError";
    this.code = code;
    this.path = [...path];
  }
}

export type ContentJsonParseErrorCode =
  | "INVALID_JSON"
  | "DUPLICATE_KEY"
  | "SOURCE_TOO_LARGE"
  | "NESTING_TOO_DEEP";

export class ContentJsonParseError extends SyntaxError {
  readonly code: ContentJsonParseErrorCode;
  readonly path: JsonPath;
  readonly index: number;

  constructor(code: ContentJsonParseErrorCode, path: JsonPath, index: number, message: string) {
    super(message);
    this.name = "ContentJsonParseError";
    this.code = code;
    this.path = [...path];
    this.index = index;
  }
}

export interface CanonicalJsonOptions {
  /** Keys omitted at the root only. Nested keys with the same name remain covered. */
  omitTopLevel?: readonly string[];
}

const MAX_JSON_SOURCE_LENGTH = 2_000_000;
const MAX_JSON_NESTING = 64;
const JSON_NUMBER = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/;

/**
 * Parses untrusted JSON while key spelling information still exists.
 *
 * JavaScript objects cannot represent duplicate JSON keys: `JSON.parse` keeps only
 * the final value. File/network callers must therefore use this boundary before
 * passing the resulting value to canonicalization or schema validation.
 */
export function parseJsonStrict(source: string): unknown {
  return new StrictJsonScanner(source).parse();
}

class StrictJsonScanner {
  private index = 0;

  constructor(private readonly source: string) {}

  parse(): unknown {
    if (this.source.length > MAX_JSON_SOURCE_LENGTH) {
      this.fail("SOURCE_TOO_LARGE", [], 0, `JSON source exceeds ${MAX_JSON_SOURCE_LENGTH} characters`);
    }

    this.skipWhitespace();
    this.scanValue([], 0);
    this.skipWhitespace();
    if (this.index !== this.source.length) {
      this.fail("INVALID_JSON", [], this.index, "Unexpected trailing JSON input");
    }

    try {
      return JSON.parse(this.source) as unknown;
    } catch (error) {
      const message = error instanceof Error ? error.message : "Malformed JSON";
      this.fail("INVALID_JSON", [], this.index, message);
    }
  }

  private scanValue(path: (string | number)[], depth: number): void {
    if (depth > MAX_JSON_NESTING) {
      this.fail("NESTING_TOO_DEEP", path, this.index, `JSON nesting exceeds ${MAX_JSON_NESTING}`);
    }

    this.skipWhitespace();
    const character = this.source[this.index];
    if (character === "{") {
      this.scanObject(path, depth);
      return;
    }
    if (character === "[") {
      this.scanArray(path, depth);
      return;
    }
    if (character === '"') {
      this.scanString(path);
      return;
    }
    if (character === "-" || (character !== undefined && character >= "0" && character <= "9")) {
      this.scanNumber(path);
      return;
    }
    if (this.consumeLiteral("true") || this.consumeLiteral("false") || this.consumeLiteral("null")) {
      return;
    }
    this.fail("INVALID_JSON", path, this.index, "Expected a JSON value");
  }

  private scanObject(path: (string | number)[], depth: number): void {
    this.index += 1;
    this.skipWhitespace();
    if (this.source[this.index] === "}") {
      this.index += 1;
      return;
    }

    const keys = new Set<string>();
    while (this.index < this.source.length) {
      this.skipWhitespace();
      const keyIndex = this.index;
      if (this.source[this.index] !== '"') {
        this.fail("INVALID_JSON", path, this.index, "Expected a quoted object key");
      }
      const key = this.scanString(path);
      if (keys.has(key)) {
        this.fail("DUPLICATE_KEY", [...path, key], keyIndex, `Duplicate object key: ${key}`);
      }
      keys.add(key);

      this.skipWhitespace();
      if (this.source[this.index] !== ":") {
        this.fail("INVALID_JSON", [...path, key], this.index, "Expected ':' after object key");
      }
      this.index += 1;
      this.scanValue([...path, key], depth + 1);
      this.skipWhitespace();

      const separator = this.source[this.index];
      if (separator === "}") {
        this.index += 1;
        return;
      }
      if (separator !== ",") {
        this.fail("INVALID_JSON", path, this.index, "Expected ',' or '}' in object");
      }
      this.index += 1;
    }

    this.fail("INVALID_JSON", path, this.index, "Unterminated object");
  }

  private scanArray(path: (string | number)[], depth: number): void {
    this.index += 1;
    this.skipWhitespace();
    if (this.source[this.index] === "]") {
      this.index += 1;
      return;
    }

    let itemIndex = 0;
    while (this.index < this.source.length) {
      this.scanValue([...path, itemIndex], depth + 1);
      itemIndex += 1;
      this.skipWhitespace();

      const separator = this.source[this.index];
      if (separator === "]") {
        this.index += 1;
        return;
      }
      if (separator !== ",") {
        this.fail("INVALID_JSON", path, this.index, "Expected ',' or ']' in array");
      }
      this.index += 1;
    }

    this.fail("INVALID_JSON", path, this.index, "Unterminated array");
  }

  private scanString(path: (string | number)[]): string {
    const start = this.index;
    this.index += 1;

    while (this.index < this.source.length) {
      const codePoint = this.source.charCodeAt(this.index);
      const character = this.source[this.index];
      if (character === '"') {
        this.index += 1;
        const token = this.source.slice(start, this.index);
        try {
          const parsed = JSON.parse(token) as unknown;
          if (typeof parsed !== "string") {
            this.fail("INVALID_JSON", path, start, "Expected a JSON string");
          }
          return parsed;
        } catch (error) {
          if (error instanceof ContentJsonParseError) {
            throw error;
          }
          this.fail("INVALID_JSON", path, start, "Malformed JSON string");
        }
      }
      if (codePoint < 0x20) {
        this.fail("INVALID_JSON", path, this.index, "Unescaped control character in string");
      }
      if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
        const lowSurrogate = this.source.charCodeAt(this.index + 1);
        if (!(lowSurrogate >= 0xdc00 && lowSurrogate <= 0xdfff)) {
          this.fail("INVALID_JSON", path, this.index, "Unpaired Unicode surrogate");
        }
        this.index += 2;
        continue;
      }
      if (codePoint >= 0xdc00 && codePoint <= 0xdfff) {
        this.fail("INVALID_JSON", path, this.index, "Unpaired Unicode surrogate");
      }
      if (character === "\\") {
        this.index += 1;
        const escape = this.source[this.index];
        if (escape === undefined) {
          this.fail("INVALID_JSON", path, this.index, "Unterminated string escape");
        }
        if (escape === "u") {
          const hexadecimal = this.source.slice(this.index + 1, this.index + 5);
          if (!/^[0-9a-fA-F]{4}$/.test(hexadecimal)) {
            this.fail("INVALID_JSON", path, this.index, "Malformed Unicode escape");
          }
          const codeUnit = Number.parseInt(hexadecimal, 16);
          if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
            if (this.source.slice(this.index + 5, this.index + 7) !== "\\u") {
              this.fail("INVALID_JSON", path, this.index, "Unpaired Unicode surrogate");
            }
            const lowHexadecimal = this.source.slice(this.index + 7, this.index + 11);
            if (!/^[0-9a-fA-F]{4}$/.test(lowHexadecimal)) {
              this.fail("INVALID_JSON", path, this.index, "Malformed Unicode surrogate");
            }
            const lowCodeUnit = Number.parseInt(lowHexadecimal, 16);
            if (lowCodeUnit < 0xdc00 || lowCodeUnit > 0xdfff) {
              this.fail("INVALID_JSON", path, this.index, "Unpaired Unicode surrogate");
            }
            this.index += 11;
            continue;
          }
          if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
            this.fail("INVALID_JSON", path, this.index, "Unpaired Unicode surrogate");
          }
          this.index += 5;
          continue;
        }
        if (!['"', "\\", "/", "b", "f", "n", "r", "t"].includes(escape)) {
          this.fail("INVALID_JSON", path, this.index, "Unsupported string escape");
        }
      }
      this.index += 1;
    }

    this.fail("INVALID_JSON", path, start, "Unterminated string");
  }

  private scanNumber(path: (string | number)[]): void {
    const match = JSON_NUMBER.exec(this.source.slice(this.index));
    if (match === null) {
      this.fail("INVALID_JSON", path, this.index, "Malformed JSON number");
    }
    this.index += match[0].length;
  }

  private consumeLiteral(literal: string): boolean {
    if (!this.source.startsWith(literal, this.index)) {
      return false;
    }
    this.index += literal.length;
    return true;
  }

  private skipWhitespace(): void {
    while (/\s/.test(this.source[this.index] ?? "") && " \t\r\n".includes(this.source[this.index] ?? "")) {
      this.index += 1;
    }
  }

  private fail(code: ContentJsonParseErrorCode, path: JsonPath, index: number, message: string): never {
    throw new ContentJsonParseError(code, path, index, message);
  }
}

export function canonicalJson(value: unknown, options: CanonicalJsonOptions = {}): string {
  const omittedRootKeys = new Set(options.omitTopLevel ?? []);
  return serializeCanonical(value, [], 0, omittedRootKeys, new Set<object>());
}

function serializeCanonical(
  value: unknown,
  path: (string | number)[],
  depth: number,
  omittedRootKeys: ReadonlySet<string>,
  ancestors: Set<object>,
): string {
  if (value === null) {
    return "null";
  }

  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "string":
      assertWellFormedUnicode(value, path);
      return JSON.stringify(value);
    case "number": {
      if (!Number.isFinite(value)) {
        throw new CanonicalJsonError("NON_FINITE_NUMBER", path, "Canonical JSON requires finite numbers");
      }
      if (Number.isInteger(value) && !Number.isSafeInteger(value)) {
        throw new CanonicalJsonError("UNSAFE_INTEGER", path, "Canonical JSON requires safe integers");
      }
      return JSON.stringify(value);
    }
    case "undefined":
    case "function":
    case "symbol":
    case "bigint":
      throw new CanonicalJsonError(
        "UNSUPPORTED_TYPE",
        path,
        `Canonical JSON does not support ${typeof value}`,
      );
    case "object":
      break;
  }

  if (ancestors.has(value)) {
    throw new CanonicalJsonError("CYCLE", path, "Canonical JSON cannot contain reference cycles");
  }
  ancestors.add(value);

  try {
    if (Array.isArray(value)) {
      validateArrayProperties(value, path);
      const items: string[] = [];
      for (let index = 0; index < value.length; index += 1) {
        if (!Object.hasOwn(value, index)) {
          throw new CanonicalJsonError("SPARSE_ARRAY", [...path, index], "Sparse arrays are not JSON values");
        }
        items.push(serializeCanonical(value[index], [...path, index], depth + 1, omittedRootKeys, ancestors));
      }
      return `[${items.join(",")}]`;
    }

    const prototype = Object.getPrototypeOf(value) as object | null;
    if (prototype !== Object.prototype && prototype !== null) {
      throw new CanonicalJsonError(
        "NON_PLAIN_OBJECT",
        path,
        "Canonical JSON accepts only arrays and plain objects",
      );
    }

    const entries: string[] = [];
    const keys = validateObjectProperties(value as Record<string, unknown>, path)
      .filter((key) => depth !== 0 || !omittedRootKeys.has(key))
      .sort(compareCodeUnits);
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (descriptor === undefined || !("value" in descriptor)) {
        throw new CanonicalJsonError("ACCESSOR_PROPERTY", [...path, key], "Accessors are not JSON values");
      }
      const encodedValue = serializeCanonical(
        descriptor.value,
        [...path, key],
        depth + 1,
        omittedRootKeys,
        ancestors,
      );
      entries.push(`${JSON.stringify(key)}:${encodedValue}`);
    }
    return `{${entries.join(",")}}`;
  } finally {
    ancestors.delete(value);
  }
}

function validateArrayProperties(value: unknown[], path: JsonPath): void {
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key === "symbol") {
      throw new CanonicalJsonError("SYMBOL_KEY", path, "Symbol-keyed values are not JSON values");
    }
    if (key === "length") {
      continue;
    }
    const index = Number(key);
    if (!Number.isSafeInteger(index) || index < 0 || String(index) !== key || index >= value.length) {
      throw new CanonicalJsonError("NON_PLAIN_OBJECT", [...path, key], "Array has a non-index property");
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor === undefined || !("value" in descriptor) || !descriptor.enumerable) {
      throw new CanonicalJsonError("ACCESSOR_PROPERTY", [...path, index], "Array accessors are not JSON values");
    }
  }
}

function validateObjectProperties(value: Record<string, unknown>, path: JsonPath): string[] {
  const keys: string[] = [];
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key === "symbol") {
      throw new CanonicalJsonError("SYMBOL_KEY", path, "Symbol-keyed values are not JSON values");
    }
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor === undefined || !("value" in descriptor) || !descriptor.enumerable) {
      throw new CanonicalJsonError("ACCESSOR_PROPERTY", [...path, key], "Accessors are not JSON values");
    }
    assertWellFormedUnicode(key, [...path, key]);
    keys.push(key);
  }
  return keys;
}

function assertWellFormedUnicode(value: string, path: JsonPath): void {
  for (let index = 0; index < value.length; index += 1) {
    const codeUnit = value.charCodeAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      const lowCodeUnit = value.charCodeAt(index + 1);
      if (!(lowCodeUnit >= 0xdc00 && lowCodeUnit <= 0xdfff)) {
        throw new CanonicalJsonError(
          "LONE_SURROGATE",
          path,
          "Canonical JSON rejects unpaired UTF-16 surrogates",
        );
      }
      index += 1;
      continue;
    }
    if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      throw new CanonicalJsonError(
        "LONE_SURROGATE",
        path,
        "Canonical JSON rejects unpaired UTF-16 surrogates",
      );
    }
  }
}

function compareCodeUnits(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
