import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

import { SupabaseCloud } from "./supabase_cloud";

function queryResult(data: unknown, error: { message: string } | null = null) {
  const result = { data, error };
  const query = {
    select: vi.fn(() => query),
    eq: vi.fn(() => query),
    is: vi.fn(() => query),
    gte: vi.fn(() => query),
    order: vi.fn(async () => result),
    limit: vi.fn(async () => result),
    single: vi.fn(async () => result),
    then: (resolve: (value: typeof result) => unknown) => Promise.resolve(result).then(resolve),
  };
  return query;
}

function clientFixture(options: {
  membershipRows?: unknown;
  childRows?: unknown;
  globalRole?: "owner" | "editor";
  appRole?: unknown;
}) {
  const membershipQuery = queryResult(options.membershipRows ?? []);
  const childQuery = queryResult(options.childRows ?? []);
  const from = vi.fn((table: string) =>
    table === "family_memberships" ? membershipQuery : childQuery,
  );
  const client = {
    auth: {
      getSession: vi.fn(async () => ({
        data: {
          session: {
            user: { id: "6f80625c-d4c0-4935-a213-2a164a37f27b", app_metadata: { role: options.appRole } },
          },
        },
        error: null,
      })),
    },
    from,
    rpc: vi.fn(async (name: string, input: { required_role?: string }) => ({
      data: name === "has_global_studio_role" && input.required_role === options.globalRole,
      error: null,
    })),
  } as unknown as SupabaseClient;
  return { client, from };
}

describe("SupabaseCloud", () => {
  it("uses an active server membership instead of trusting app metadata", async () => {
    const { client } = clientFixture({
      appRole: "admin",
      membershipRows: [{ role: "guardian" }],
    });

    await expect(new SupabaseCloud(client).session()).resolves.toEqual({
      status: "authenticated",
      userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
      role: "guardian",
    });
  });

  it("fails closed when an authenticated user has no approved role", async () => {
    const { client } = clientFixture({ appRole: "admin", membershipRows: [] });

    await expect(new SupabaseCloud(client).session()).resolves.toEqual({
      status: "unauthorized",
      userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
    });
  });

  it("maps a family owner to guardian when no global Studio claim exists", async () => {
    const { client } = clientFixture({ membershipRows: [{ role: "owner" }] });

    await expect(new SupabaseCloud(client).session()).resolves.toEqual({
      status: "authenticated",
      userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
      role: "guardian",
    });
  });

  it("does not grant Studio access to a family editor", async () => {
    const { client } = clientFixture({ membershipRows: [{ role: "editor" }] });

    await expect(new SupabaseCloud(client).session()).resolves.toEqual({
      status: "unauthorized",
      userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
    });
  });

  it("prefers the server-checked global Studio claim over family membership", async () => {
    const { client } = clientFixture({
      membershipRows: [{ role: "guardian" }],
      globalRole: "owner",
    });

    await expect(new SupabaseCloud(client).session()).resolves.toEqual({
      status: "authenticated",
      userId: "6f80625c-d4c0-4935-a213-2a164a37f27b",
      role: "owner",
    });
  });

  it("rejects malformed or cross-family child rows", async () => {
    const { client } = clientFixture({
      childRows: [
        { id: 42, family_id: "family-b", nickname: null, devices: [{ last_sync_at: 7 }] },
      ],
    });

    await expect(new SupabaseCloud(client).listChildren("family-a")).rejects.toThrow(
      /list children/i,
    );
  });

  it("loads publication history only through the function boundary", async () => {
    const invoke = vi.fn(async () => ({
      data: [{
        id: "40000000-0000-4000-8000-000000000001",
        activityId: "addition_ones",
        contentVersion: "1.0.0",
        checksum: `sha256:${"a".repeat(64)}`,
        status: "active",
        publishedAt: "2030-01-01T00:00:00.000Z",
        effectiveAt: "2030-01-01T00:00:00.000Z",
        publishedBy: "00000000-0000-4000-8000-000000000001",
        sourceRevision: 3,
        rollbackOfId: null,
        reason: "첫 배포",
        validationValid: true,
      }],
      error: null,
    }));
    const client = { functions: { invoke } } as unknown as SupabaseClient;

    await expect(new SupabaseCloud(client).listPublicationHistory("addition_ones")).resolves.toHaveLength(1);
    expect(invoke).toHaveBeenCalledWith("content-history", { body: { activityId: "addition_ones" } });
  });
});
