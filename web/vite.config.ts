import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  base: "/Mathland_new2/",
  plugins: [react()],
  build: {
    outDir: "dist",
    sourcemap: true,
  },
});
