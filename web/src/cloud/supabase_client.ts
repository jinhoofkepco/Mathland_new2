import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { RuntimeEnv } from "../config/runtime_env";

export function createSupabaseBrowserClient(
  env: Extract<RuntimeEnv, { mode: "supabase" }>,
): SupabaseClient {
  return createClient(env.supabaseUrl, env.supabasePublishableKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: "pkce",
    },
  });
}
