import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../..");
const workflowPath = path.join(repoRoot, ".github/workflows/web.yml");

describe("GitHub Pages workflow", () => {
  it("tests a credential-free build and deploys only web/dist from main", () => {
    const workflow = readFileSync(workflowPath, "utf8");

    expect(workflow).toMatch(/branches:\s*\[main\]/u);
    expect(workflow).toContain("VITE_MATHLAND_CLOUD_MODE: fake");
    expect(workflow).toContain("path: web/dist");
    expect(workflow).toContain("actions/deploy-pages@v4");
    expect(workflow).toContain("pages: write");
    expect(workflow).toContain("id-token: write");
    expect(workflow).not.toContain("pull_request_target");
    expect(workflow).not.toMatch(/service[_-]?role/iu);
  });
});
