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
  const mode = requiredString(record, "VITE_MATHLAND_CLOUD_MODE");
  if (mode === "fake") {
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
