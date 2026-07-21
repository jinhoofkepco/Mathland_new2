import { describe, expect, it } from "vitest";

import {
  ChildProfileRowSchema,
  CreateGuardianRewardInputSchema,
  DuePublicationBatchLimitSchema,
  FamilyMembershipRowSchema,
  GuardianRewardProjectionRowSchema,
  PublicationReasonSchema,
  SessionStateSchema,
  UpdateGuardianRewardInputSchema,
} from "../../src/cloud/wire.js";

describe("cloud wire contracts", () => {
  it("accepts a strict family membership projection", () => {
    expect(
      FamilyMembershipRowSchema.parse({
        role: "guardian",
        family: {
          id: "d4b3d8da-b8de-477b-b580-0712b5264b99",
          name: "모아네 가족",
        },
      }),
    ).toBeTruthy();
  });

  it("rejects malformed child projections before the dashboard sees them", () => {
    expect(() =>
      ChildProfileRowSchema.parse({
        id: 42,
        family_id: "different-family",
        nickname: null,
        devices: [{ last_sync_at: 7 }],
      }),
    ).toThrow();
  });

  it("does not invent a guardian role for an unknown session", () => {
    expect(() =>
      SessionStateSchema.parse({
        status: "authenticated",
        userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
        role: "admin",
      }),
    ).toThrow();
  });

  it("accepts only the safe guardian reward projection and bounded mutations", () => {
    expect(
      GuardianRewardProjectionRowSchema.parse({
        id: "40000000-0000-4000-8000-000000000001",
        profile_id: "20000000-0000-4000-8000-000000000001",
        title: "공원 가기",
        required_apples: 12,
        status: "available",
        created_at: "2026-07-22T01:02:03Z",
        claimed_at: null,
      }),
    ).not.toHaveProperty("created_by");
    expect(() =>
      GuardianRewardProjectionRowSchema.parse({
        id: "40000000-0000-4000-8000-000000000001",
        profile_id: "20000000-0000-4000-8000-000000000001",
        title: "공원 가기",
        required_apples: 12,
        status: "available",
        created_at: "2026-07-22T01:02:03Z",
        claimed_at: null,
        created_by: "00000000-0000-4000-8000-000000000001",
      }),
    ).toThrow();

    expect(
      CreateGuardianRewardInputSchema.parse({
        profileId: "20000000-0000-4000-8000-000000000001",
        title: "  공원 가기  ",
        requiredApples: 12,
      }).title,
    ).toBe("공원 가기");

    expect(() =>
      UpdateGuardianRewardInputSchema.parse({
        rewardId: "40000000-0000-4000-8000-000000000001",
        title: "현금",
        requiredApples: Number.MAX_SAFE_INTEGER + 1,
        status: "claimed",
      }),
    ).toThrow();
  });

  it("rejects null/unbounded worker limits and every whitespace-only reason", () => {
    expect(DuePublicationBatchLimitSchema.parse(100)).toBe(100);
    expect(() => DuePublicationBatchLimitSchema.parse(null)).toThrow();
    expect(() => DuePublicationBatchLimitSchema.parse(101)).toThrow();
    expect(() => PublicationReasonSchema.parse("\n\t\r")).toThrow();
    expect(PublicationReasonSchema.parse("  현장 난이도 조정  ")).toBe(
      "현장 난이도 조정",
    );
  });
});
