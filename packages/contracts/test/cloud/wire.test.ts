import { describe, expect, it } from "vitest";

import {
  ChildProfileRowSchema,
  FamilyMembershipRowSchema,
  SessionStateSchema,
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
});
