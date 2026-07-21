import { describe, expect, it } from "vitest";

import type { FakeCloudDataset } from "./fake_cloud";
import { FakeCloud } from "./fake_cloud";

const dataset: FakeCloudDataset = {
  session: { status: "authenticated", userId: "guardian-1", role: "guardian" },
  families: [
    { id: "family-a", name: "모아네 가족", role: "guardian" },
    { id: "family-b", name: "별이네 가족", role: "guardian" },
  ],
  children: [
    { id: "child-a1", familyId: "family-a", nickname: "서아", lastSyncAt: "2026-07-21T08:00:00.000Z" },
    { id: "child-b1", familyId: "family-b", nickname: "별이", lastSyncAt: null },
    { id: "child-a2", familyId: "family-a", nickname: "도윤", lastSyncAt: "2026-07-21T07:30:00.000Z" },
  ],
  dashboards: {
    "family-a": {
      familyId: "family-a",
      generatedAt: "2026-07-21T08:01:00.000Z",
      sessions: [
        { runId: "run-new", profileId: "child-a1", startedAt: "2026-07-21T07:50:00.000Z", score: 9 },
        { runId: "run-old", profileId: "child-a2", startedAt: "2026-07-20T06:00:00.000Z", score: 7 },
      ],
    },
  },
};

describe("FakeCloud", () => {
  it("isolates children by requested family", async () => {
    const cloud = new FakeCloud(dataset);

    await expect(cloud.listChildren("family-a")).resolves.toEqual([
      dataset.children[0],
      dataset.children[2],
    ]);
    await expect(cloud.listChildren("family-b")).resolves.toEqual([dataset.children[1]]);
  });

  it("preserves aggregate ordering and returns detached values", async () => {
    const cloud = new FakeCloud(dataset);

    const first = await cloud.dashboard({ familyId: "family-a", range: "7d" });
    expect(first.sessions.map((session) => session.runId)).toEqual(["run-new", "run-old"]);

    first.sessions.reverse();
    const second = await cloud.dashboard({ familyId: "family-a", range: "7d" });
    expect(second.sessions.map((session) => session.runId)).toEqual(["run-new", "run-old"]);
  });

  it("fails closed for an unknown family dashboard", async () => {
    const cloud = new FakeCloud(dataset);

    await expect(cloud.dashboard({ familyId: "missing", range: "30d" })).rejects.toThrow(
      /not available/i,
    );
  });
});
