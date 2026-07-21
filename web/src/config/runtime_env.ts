export type RuntimeEnv =
  | { mode: "fake" }
  | {
      mode: "supabase";
      supabaseUrl: string;
      supabasePublishableKey: string;
    };

export class RuntimeEnvError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RuntimeEnvError";
  }
}

const ALLOWED_CLIENT_ENV_KEYS = new Set([
  "VITE_MATHLAND_CLOUD_MODE",
  "VITE_SUPABASE_URL",
  "VITE_SUPABASE_PUBLISHABLE_KEY",
]);

export function assertSafeClientEnvKeys(record: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(record)) {
    if (
      key.startsWith("VITE_") &&
      !ALLOWED_CLIENT_ENV_KEYS.has(key) &&
      value !== undefined &&
      value !== ""
    ) {
      throw new RuntimeEnvError(`${key} is not allowed in the browser bundle`);
    }
  }
}

function requiredString(record: Record<string, unknown>, key: string): string {
  const value = record[key];
  if (typeof value !== "string" || value.trim() === "") {
    throw new RuntimeEnvError(`${key} is required`);
  }
  return value.trim();
}

function parseSupabaseUrl(raw: string): string {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new RuntimeEnvError("VITE_SUPABASE_URL must be a valid HTTPS Supabase project URL");
  }

  const isProjectHost = /^[a-z0-9-]+\.supabase\.co$/i.test(url.hostname);
  if (
    url.protocol !== "https:" ||
    !isProjectHost ||
    url.username !== "" ||
    url.password !== "" ||
    url.port !== "" ||
    url.pathname !== "/" ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new RuntimeEnvError("VITE_SUPABASE_URL must be a valid HTTPS Supabase project URL");
  }
  return url.origin;
}

function parsePublishableKey(raw: string): string {
  const normalized = raw.trim();
  if (
    /service[_-]?role/i.test(normalized) ||
    !/^sb_publishable_[A-Za-z0-9._-]{8,}$/.test(normalized)
  ) {
    throw new RuntimeEnvError(
      "VITE_SUPABASE_PUBLISHABLE_KEY must contain only a Supabase publishable browser key",
    );
  }
  return normalized;
}

export function parseRuntimeEnv(record: Record<string, unknown>): RuntimeEnv {
  assertSafeClientEnvKeys(record);
  const mode = requiredString(record, "VITE_MATHLAND_CLOUD_MODE");
  if (mode === "fake") {
    if (
      (typeof record.VITE_SUPABASE_URL === "string" && record.VITE_SUPABASE_URL.trim() !== "") ||
      (typeof record.VITE_SUPABASE_PUBLISHABLE_KEY === "string" &&
        record.VITE_SUPABASE_PUBLISHABLE_KEY.trim() !== "")
    ) {
      throw new RuntimeEnvError("Supabase credentials must be absent in fake mode");
    }
    return { mode: "fake" };
  }
  if (mode !== "supabase") {
    throw new RuntimeEnvError("VITE_MATHLAND_CLOUD_MODE must be fake or supabase");
  }

  return {
    mode: "supabase",
    supabaseUrl: parseSupabaseUrl(requiredString(record, "VITE_SUPABASE_URL")),
    supabasePublishableKey: parsePublishableKey(
      requiredString(record, "VITE_SUPABASE_PUBLISHABLE_KEY"),
    ),
  };
}

export function parseRuntimeEnvWithDemoDefault(record: Record<string, unknown>): RuntimeEnv {
  assertSafeClientEnvKeys(record);
  const rawMode = record.VITE_MATHLAND_CLOUD_MODE;
  const hasMode = typeof rawMode === "string" && rawMode.trim() !== "";
  const hasCloudValue = [
    record.VITE_SUPABASE_URL,
    record.VITE_SUPABASE_PUBLISHABLE_KEY,
  ].some((value) => typeof value === "string" && value.trim() !== "");

  if (!hasMode && !hasCloudValue) {
    return { mode: "fake" };
  }
  if (!hasMode) {
    throw new RuntimeEnvError(
      "VITE_MATHLAND_CLOUD_MODE cloud mode is required when Supabase configuration is present",
    );
  }
  return parseRuntimeEnv(record);
}
