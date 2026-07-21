import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = resolve("scripts/android/stage_project.sh");

function write(root, path, contents = path) {
  const target = join(root, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, contents);
}

function listFiles(root, current = root) {
  const entries = [];
  for (const name of readdirSync(current, { withFileTypes: true })) {
    const path = join(current, name.name);
    if (name.isDirectory()) entries.push(...listFiles(root, path));
    else entries.push(`${relative(root, path)}:${readFileSync(path, "utf8")}`);
  }
  return entries.sort();
}

function makeSource(root, includeHostArtifacts) {
  write(root, "project.godot", "[application]");
  write(root, "src/app.gd", "extends Node");
  write(root, "assets/moa.svg", "<svg />");
  write(root, "addons/mathland_secure_credentials/bin/debug/plugin.aar", "aar");
  if (!includeHostArtifacts) return;
  write(root, "package.json", "host package");
  write(root, "package-lock.json", "host lock");
  write(root, "node_modules/example/index.js", "dependency");
  write(root, "packages/contracts/node_modules/example/index.js", "nested dependency");
  write(root, ".godot/editor/project_metadata.cfg", "editor cache");
  write(root, ".git", "gitdir: linked-worktree");
  write(root, ".github/workflows/ci.yml", "host workflow");
  write(root, "android/build/intermediates/output.bin", "gradle output");
  write(root, "reports/test.xml", "report");
  write(root, ".env.local", "secret");
  write(root, "release.keystore", "secret key");
  write(root, ".DS_Store", "finder");
}

test("staged runtime listing is identical with or without npm and host artifacts", () => {
  const root = mkdtempSync(join(tmpdir(), "mathland-export-stage-"));
  try {
    const cleanSource = join(root, "clean-source");
    const npmSource = join(root, "npm-source");
    const cleanStage = join(root, "clean-stage");
    const npmStage = join(root, "npm-stage");
    mkdirSync(cleanSource);
    mkdirSync(npmSource);
    makeSource(cleanSource, false);
    makeSource(npmSource, true);

    for (const [source, stage] of [[cleanSource, cleanStage], [npmSource, npmStage]]) {
      const result = spawnSync("bash", [script, source, stage], { encoding: "utf8" });
      assert.equal(result.status, 0, result.stderr);
    }

    const expected = [
      "addons/mathland_secure_credentials/bin/debug/plugin.aar:aar",
      "assets/moa.svg:<svg />",
      "project.godot:[application]",
      "src/app.gd:extends Node",
    ];
    assert.deepEqual(listFiles(cleanStage), expected);
    assert.deepEqual(listFiles(npmStage), expected);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
