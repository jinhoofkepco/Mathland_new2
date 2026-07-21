import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const rootPackage = JSON.parse(
  readFileSync(new URL("../../../../package.json", import.meta.url), "utf8"),
) as { scripts?: Record<string, unknown> };

describe("root workspace scripts", () => {
  it("leaves Vitest run-mode and filters to the test:content-tools caller", () => {
    expect(rootPackage.scripts?.["test:content-tools"]).toBe(
      "npm --workspace @mathland/contracts test --",
    );
  });
});
