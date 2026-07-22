import { describe, expect, it } from "vitest";

import type { FakeCloudDataset } from "./fake_cloud";
import { createDemoFakeCloud, FakeCloud } from "./fake_cloud";

const dataset: FakeCloudDataset = {
  session: { status: "authenticated", userId: "guardian-1", role: "guardian", familyStatus: "ready" },
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
      activities: [],
      errors: [],
      rewards: [],
    },
  },
};

describe("FakeCloud", () => {
  it("models first-run onboarding as a one-time state transition", async () => {
    const cloud = new FakeCloud({
      session: { status: "onboarding", userId: "00000000-0000-4000-8000-000000000099" },
      families: [],
      children: [],
      dashboards: {},
    });

    const created = await cloud.bootstrapGuardian({
      familyName: " 모아네 가족 ",
      childNickname: " 모아 ",
    });

    await expect(cloud.session()).resolves.toMatchObject({
      status: "authenticated",
      role: "guardian",
    });
    await expect(cloud.listFamilies()).resolves.toEqual([
      { id: created.familyId, name: "모아네 가족", role: "guardian" },
    ]);
    await expect(cloud.listChildren(created.familyId)).resolves.toEqual([
      { id: created.profileId, familyId: created.familyId, nickname: "모아", lastSyncAt: null },
    ]);
    await expect(
      cloud.bootstrapGuardian({ familyName: "두 번째", childNickname: "아이" }),
    ).rejects.toThrow(/not available/i);
  });

  it("preserves a global Studio role while adding guardian family access", async () => {
    const cloud = new FakeCloud({
      session: {
        status: "authenticated",
        userId: "00000000-0000-4000-8000-000000000098",
        role: "owner",
        familyStatus: "onboarding",
      },
      families: [], children: [], dashboards: {},
    });

    await cloud.bootstrapGuardian({ familyName: "운영자 가족", childNickname: "아이" });

    await expect(cloud.session()).resolves.toEqual({
      status: "authenticated",
      userId: "00000000-0000-4000-8000-000000000098",
      role: "owner",
      familyStatus: "ready",
    });
  });

  it("ships a clearly synthetic, signed-in Pages demo", async () => {
    const cloud = createDemoFakeCloud();

    await expect(cloud.session()).resolves.toMatchObject({
      status: "authenticated",
      role: "owner",
    });
    await expect(cloud.listFamilies()).resolves.toEqual([
      expect.objectContaining({ name: "MathLand 데모 가족" }),
    ]);
    await expect(cloud.listChildren("00000000-0000-4000-8000-000000000001")).resolves.toEqual([
      expect.objectContaining({ nickname: "데모 아이" }),
    ]);
    await expect(cloud.listDrafts()).resolves.toEqual([
      expect.objectContaining({ activityId: "addition_ones", title: "덧셈 탐험" }),
    ]);
  });

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
