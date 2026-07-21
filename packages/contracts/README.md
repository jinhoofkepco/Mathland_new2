# `@mathland/contracts`

This private workspace is the source-first TypeScript contract boundary for MathLand content tools, the web application, and edge-function development. Its package exports intentionally point to `src/*.ts` and are consumed through the repository's TypeScript-aware tooling (`tsx`, Vite, and Vitest).

It is not currently a native Node.js JavaScript distribution. Do not import it directly from untranspiled Node ESM or add hand-written JavaScript beside the TypeScript sources. If a future delivery target requires native Node consumption, add a planned build that emits ESM plus declaration files and then move the package exports to those generated artifacts.
