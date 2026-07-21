import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const scanner = path.join(repoRoot, "scripts/scan_client_secrets.sh");
const temporaryRoots: string[] = [];

function fixture(contents: string): string {
  const root = mkdtempSync(path.join(tmpdir(), "mathland-client-scan-"));
  temporaryRoots.push(root);
  writeFileSync(path.join(root, "bundle.js"), contents, "utf8");
  return root;
}

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) rmSync(root, { recursive: true, force: true });
});

describe("client secret scanner", () => {
  it("allows only public client configuration in a bundle", () => {
    const root = fixture(
      'const url="https://example.supabase.co";const key="sb_publishable_example123";',
    );

    expect(() => execFileSync("bash", [scanner, root], { stdio: "pipe" })).not.toThrow();
  });

  it("fails closed when the required scanner is unavailable", () => {
    const root = fixture('const key="sb_publishable_example123";');

    expect(() =>
      execFileSync("bash", [scanner, root], {
        env: { ...process.env, MATHLAND_RG_BIN: "/definitely/missing/rg" },
        stdio: "pipe",
      }),
    ).toThrow();
  });

  it.each([
    "sb_secret_accidental-browser-key",
    "service_role.accidental-browser-key",
    "-----BEGIN PRIVATE KEY-----",
    "https://localhost:54321",
  ])("rejects privileged or development material: %s", (secret) => {
    const root = fixture(`window.__config=${JSON.stringify(secret)}`);

    expect(() => execFileSync("bash", [scanner, root], { stdio: "pipe" })).toThrow();
  });
});
