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

  it.each(["VITE_SUPABASE_SERVICE_ROLE_KEY", "VITE_OPENAI_API_KEY", "VITE_AI_SECRET"])(
    "rejects forbidden client environment names even in fake mode: %s",
    (name) => {
      expect(() =>
        parseRuntimeEnv({ VITE_MATHLAND_CLOUD_MODE: "fake", [name]: "must-not-bundle" }),
      ).toThrow(/not allowed in the browser/i);
    },
  );

  it("rejects cloud credentials left behind while fake mode is selected", () => {
    expect(() =>
      parseRuntimeEnv({
        VITE_MATHLAND_CLOUD_MODE: "fake",
        VITE_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_accidental-key",
      }),
    ).toThrow(/fake mode/i);
  });
});
