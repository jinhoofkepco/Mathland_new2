import { describe, expect, it } from "vitest";

import { ACTIVITY_IDS, type ActivityPackageDraftV1 } from "@mathland/contracts/content";

describe("content subpath", () => {
  it("exports content allowlists and public types together", () => {
    const schemaVersion: ActivityPackageDraftV1["schema_version"] = 1;

    expect(ACTIVITY_IDS).toHaveLength(11);
    expect(schemaVersion).toBe(1);
  });
});
