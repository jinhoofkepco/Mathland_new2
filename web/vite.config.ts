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
    },
  };
});
