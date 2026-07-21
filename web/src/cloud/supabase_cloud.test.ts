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
  rpcResult?: boolean;
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
    rpc: vi.fn(async () => ({ data: options.rpcResult ?? false, error: null })),
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
});
