export type DraftChange = {
  kind: "added" | "removed" | "changed";
  path: string;
  before: unknown;
  after: unknown;
};

function pointerSegment(value: string): string {
  return value.replaceAll("~", "~0").replaceAll("/", "~1");
}

function isContainer(value: unknown): value is Record<string, unknown> | unknown[] {
  return value !== null && typeof value === "object";
}

export function diffDraft(before: unknown, after: unknown): DraftChange[] {
  const changes: DraftChange[] = [];
  const stack: Array<{ before: unknown; after: unknown; path: string }> = [
    { before, after, path: "" },
  ];
  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || Object.is(current.before, current.after)) continue;
    if (current.before === undefined || current.after === undefined) {
      changes.push({
        kind: current.before === undefined ? "added" : "removed",
        path: current.path || "/",
        before: current.before,
        after: current.after,
      });
      continue;
    }
    const bothArrays = Array.isArray(current.before) && Array.isArray(current.after);
    const bothObjects =
      !Array.isArray(current.before) &&
      !Array.isArray(current.after) &&
      isContainer(current.before) &&
      isContainer(current.after);
    if (bothArrays || bothObjects) {
      const left = current.before as Record<string, unknown>;
      const right = current.after as Record<string, unknown>;
      const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort().reverse();
      for (const key of keys) {
        stack.push({
          before: left[key],
          after: right[key],
          path: `${current.path}/${pointerSegment(key)}`,
        });
      }
      continue;
    }
    changes.push({ kind: "changed", path: current.path || "/", before: current.before, after: current.after });
  }
  return changes.sort((left, right) => left.path.localeCompare(right.path));
}
