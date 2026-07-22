import { createContext, type PropsWithChildren, useContext, useMemo } from "react";

import { parseRuntimeEnvWithDemoDefault, type RuntimeEnv } from "../config/runtime_env";
import type { CloudPort } from "./cloud_port";
import { createDemoFakeCloud } from "./fake_cloud";
import { SupabaseCloud } from "./supabase_cloud";
import { createSupabaseBrowserClient } from "./supabase_client";

const CloudContext = createContext<CloudPort | null>(null);

export function createCloud(env: RuntimeEnv): CloudPort {
  return env.mode === "fake"
    ? createDemoFakeCloud()
    : new SupabaseCloud(createSupabaseBrowserClient(env));
}

export interface CloudProviderProps extends PropsWithChildren {
  cloud?: CloudPort;
}

export function CloudProvider({ cloud, children }: CloudProviderProps) {
  const value = useMemo(
    () =>
      cloud ??
      createCloud(
        parseRuntimeEnvWithDemoDefault({
          VITE_MATHLAND_CLOUD_MODE: import.meta.env.VITE_MATHLAND_CLOUD_MODE,
          VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
          VITE_SUPABASE_PUBLISHABLE_KEY: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
        }),
      ),
    [cloud],
  );
  return <CloudContext.Provider value={value}>{children}</CloudContext.Provider>;
}

export function useCloud(): CloudPort {
  const cloud = useContext(CloudContext);
  if (!cloud) {
    throw new Error("useCloud must be used inside CloudProvider");
  }
  return cloud;
}
