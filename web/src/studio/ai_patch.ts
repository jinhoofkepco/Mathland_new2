import type { AiPatchResult } from "../cloud/cloud_port";

type JsonPatchOperation = AiPatchResult["patch"][number];
type JsonContainer = Record<string, unknown> | unknown[];

const RESERVED_SEGMENTS = new Set(["__proto__", "prototype", "constructor"]);

function decodePointer(path: string): string[] {
  if (!path.startsWith("/") || path.length > 2_048) {
    throw new Error("Patch path must be a bounded JSON pointer");
  }
  return path.slice(1).split("/").map((raw) => {
    if (/~(?:[^01]|$)/u.test(raw)) throw new Error("Patch path contains an invalid escape");
    const segment = raw.replaceAll("~1", "/").replaceAll("~0", "~");
    if (RESERVED_SEGMENTS.has(segment)) throw new Error("Patch path contains a reserved segment");
    return segment;
  });
}

function arrayIndex(segment: string, length: number, allowEnd: boolean): number {
  if (!/^(0|[1-9][0-9]*)$/u.test(segment)) throw new Error("Patch array index is invalid");
  const index = Number(segment);
  if (!Number.isSafeInteger(index) || index < 0 || index >= length + (allowEnd ? 1 : 0)) {
    throw new Error("Patch array index is outside the document");
  }
  return index;
}

function hasKey(container: JsonContainer, segment: string): boolean {
  if (Array.isArray(container)) {
    if (segment === "-") return false;
    try {
      return arrayIndex(segment, container.length, false) < container.length;
    } catch {
      return false;
    }
  }
  return Object.hasOwn(container, segment);
}

function getValue(container: JsonContainer, segment: string): unknown {
  if (Array.isArray(container)) return container[arrayIndex(segment, container.length, false)];
  return container[segment];
}

function parentAt(root: unknown, segments: string[]): { parent: JsonContainer; key: string } {
  if (segments.length === 0) throw new Error("Replacing the draft root is not allowed");
  let current = root;
  for (const segment of segments.slice(0, -1)) {
    if (current === null || typeof current !== "object" || !hasKey(current as JsonContainer, segment)) {
      throw new Error("Patch parent path does not exist");
    }
    current = getValue(current as JsonContainer, segment);
  }
  if (current === null || typeof current !== "object") throw new Error("Patch parent is not a container");
  return { parent: current as JsonContainer, key: segments.at(-1)! };
}

function sameJson(left: unknown, right: unknown): boolean {
  const stack: Array<[unknown, unknown]> = [[left, right]];
  while (stack.length > 0) {
    const pair = stack.pop()!;
    if (Object.is(pair[0], pair[1])) continue;
    if (pair[0] === null || pair[1] === null || typeof pair[0] !== "object" || typeof pair[1] !== "object") return false;
    if (Array.isArray(pair[0]) !== Array.isArray(pair[1])) return false;
    const leftKeys = Object.keys(pair[0]);
    const rightKeys = Object.keys(pair[1]);
    if (leftKeys.length !== rightKeys.length || leftKeys.some((key) => !Object.hasOwn(pair[1] as object, key))) return false;
    for (const key of leftKeys) {
      stack.push([(pair[0] as Record<string, unknown>)[key], (pair[1] as Record<string, unknown>)[key]]);
    }
  }
  return true;
}

function requireValue(operation: JsonPatchOperation): unknown {
  if (!Object.hasOwn(operation, "value") || operation.value === undefined) {
    throw new Error(`Patch ${operation.op} operation requires a JSON value`);
  }
  return structuredClone(operation.value);
}

export function applyJsonPatch<T>(source: T, operations: JsonPatchOperation[]): T {
  if (operations.length > 128) throw new Error("Patch contains too many operations");
  const result = structuredClone(source);
  for (const operation of operations) {
    const { parent, key } = parentAt(result, decodePointer(operation.path));
    if (operation.op === "test") {
      if (!hasKey(parent, key) || !sameJson(getValue(parent, key), requireValue(operation))) {
        throw new Error(`Patch test operation failed at ${operation.path}`);
      }
      continue;
    }
    if (operation.op === "remove") {
      if (!hasKey(parent, key)) throw new Error(`Patch path does not exist: ${operation.path}`);
      if (Array.isArray(parent)) parent.splice(arrayIndex(key, parent.length, false), 1);
      else delete parent[key];
      continue;
    }
    if (operation.op === "replace" && !hasKey(parent, key)) {
      throw new Error(`Patch path does not exist: ${operation.path}`);
    }
    const value = requireValue(operation);
    if (Array.isArray(parent)) {
      if (operation.op === "add") {
        const index = key === "-" ? parent.length : arrayIndex(key, parent.length, true);
        parent.splice(index, 0, value);
      } else {
        parent[arrayIndex(key, parent.length, false)] = value;
      }
    } else {
      parent[key] = value;
    }
  }
  return result;
}
