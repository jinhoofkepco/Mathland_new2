import react from "@vitejs/plugin-react";
import { defineConfig, loadEnv } from "vite";

import { assertSafeClientEnvKeys } from "./src/config/runtime_env";

export default defineConfig(({ mode }) => {
  assertSafeClientEnvKeys(loadEnv(mode, process.cwd(), ""));
  return {
    base: "/Mathland_new2/",
    plugins: [react()],
    build: {
      outDir: "dist",
      sourcemap: true,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes("/node_modules/@supabase/")) return "cloud-vendor";
            if (/\/node_modules\/(?:react|react-dom|react-router|react-router-dom|scheduler)\//u.test(id)) return "react-vendor";
            if (id.includes("/node_modules/zod/")) return "validation-vendor";
            return undefined;
          },
        },
      },
    },
  };
});
