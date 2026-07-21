import { describe, expect, it } from "vitest";

import { parseRuntimeEnv } from "./runtime_env";

describe("parseRuntimeEnv", () => {
  it("accepts an explicit Supabase project and publishable key", () => {
    expect(
      parseRuntimeEnv({
        VITE_MATHLAND_CLOUD_MODE: "supabase",
        VITE_SUPABASE_URL: "https://mathland-family.supabase.co",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_public-browser-key",
      }),
    ).toEqual({
      mode: "supabase",
      supabaseUrl: "https://mathland-family.supabase.co",
      supabasePublishableKey: "sb_publishable_public-browser-key",
    });
  });

  it("rejects a missing project URL", () => {
    expect(() =>
      parseRuntimeEnv({
        VITE_MATHLAND_CLOUD_MODE: "supabase",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_public-browser-key",
      }),
    ).toThrow(/VITE_SUPABASE_URL/);
  });

  it.each([
    "service_role",
    "service_role.super-secret",
    "eyJhbGciOiJIUzI1NiJ9.service_role.signature",
  ])("rejects privileged browser key material: %s", (key) => {
    expect(() =>
      parseRuntimeEnv({
        VITE_MATHLAND_CLOUD_MODE: "supabase",
        VITE_SUPABASE_URL: "https://mathland-family.supabase.co",
        VITE_SUPABASE_PUBLISHABLE_KEY: key,
      }),
    ).toThrow(/publishable/i);
  });

  it("supports an explicit credential-free fake mode", () => {
    expect(parseRuntimeEnv({ VITE_MATHLAND_CLOUD_MODE: "fake" })).toEqual({ mode: "fake" });
  });
});
