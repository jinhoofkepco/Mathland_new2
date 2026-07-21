import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

import { describe, expect, it } from "vitest";

const ROOT = path.resolve(new URL("../../../..", import.meta.url).pathname);

const EXPECTED_RUNTIME_ASSETS = {
  "art.collection.shells": "assets/art/collection/collection_shells.png",
  "art.island.exploration_bg": "assets/art/island/exploration_island_bg.png",
  "ui.activity.foundations_base_ten":
    "assets/ui/icons/activities/foundations_base_ten.svg",
  "ui.status.correct": "assets/ui/icons/status/correct.svg",
  "ui.status.heart": "assets/ui/icons/status/heart.svg",
  "ui.status.speaker": "assets/ui/icons/status/speaker.svg",
  "ui.status.wrong": "assets/ui/icons/status/wrong.svg",
} as const;

async function runtimeFiles(relativePath: string): Promise<string[]> {
  const absolute = path.join(ROOT, relativePath);
  const entries = await readdir(absolute, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const child = path.join(relativePath, entry.name);
      return entry.isDirectory() ? runtimeFiles(child) : [child];
    }),
  );
  return files.flat();
}

describe("runtime release asset integration", () => {
  it("maps manifest IDs to their exact reviewed release paths", async () => {
    const manifest = JSON.parse(
      await readFile(path.join(ROOT, "assets/asset-manifest.json"), "utf8"),
    ) as { assets: { id: string; path: string; release: boolean }[] };
    const catalog = await readFile(
      path.join(ROOT, "src/presentation/assets/asset_catalog.gd"),
      "utf8",
    );

    for (const [assetId, releasePath] of Object.entries(EXPECTED_RUNTIME_ASSETS)) {
      expect(
        manifest.assets.find((asset) => asset.id === assetId),
        assetId,
      ).toMatchObject({ path: releasePath, release: true });
      expect(catalog, assetId).toContain(`&"${assetId}": "res://${releasePath}"`);
    }
  });

  it("maps the vertical-slice content ID to the base-ten manifest ID", async () => {
    const content = JSON.parse(
      await readFile(
        path.join(ROOT, "resources/content/foundation_ten_rods.vertical_slice.json"),
        "utf8",
      ),
    ) as { activity_id: string };
    const catalog = await readFile(
      path.join(ROOT, "src/presentation/assets/asset_catalog.gd"),
      "utf8",
    );
    const freePlay = await readFile(path.join(ROOT, "src/ui/island/free_play.gd"), "utf8");

    expect(content.activity_id).toBe("foundation_ten_rods");
    expect(catalog).toContain(
      `&"foundation_ten_rods": &"ui.activity.foundations_base_ten"`,
    );
    expect(freePlay).toContain("AssetCatalogScript.activity_icon_id(activity_id)");
  });

  it("wires the reviewed releases into island, collection, and controls", async () => {
    const [island, collection, tactile, activityRun, tenRod] = await Promise.all([
      readFile(path.join(ROOT, "src/ui/island/exploration_island.gd"), "utf8"),
      readFile(path.join(ROOT, "src/ui/island/collection.gd"), "utf8"),
      readFile(path.join(ROOT, "src/presentation/controls/tactile_button.gd"), "utf8"),
      readFile(path.join(ROOT, "src/ui/game/activity_run.gd"), "utf8"),
      readFile(path.join(ROOT, "src/game/manipulatives/ten_rod_board.gd"), "utf8"),
    ]);

    expect(island).toContain("AssetCatalogScript.EXPLORATION_ISLAND_ID");
    expect(collection).toContain("AssetCatalogScript.collection_region(entry_key)");
    expect(collection).toContain("AssetCatalogScript.COLLECTION_SHELLS_ID");
    expect(tactile).toContain("AssetCatalogScript.texture_for(StringName(icon_name))");
    expect(activityRun).toContain('"ui.status.speaker"');
    expect(tenRod).toContain('"ui.status.correct"');
  });

  it("never references provenance-only source assets from runtime files", async () => {
    const files = [
      "project.godot",
      ...(await runtimeFiles("src")),
      ...(await runtimeFiles("scenes")),
      ...(await runtimeFiles("resources")),
    ];
    for (const relativePath of files) {
      const text = await readFile(path.join(ROOT, relativePath), "utf8").catch(() => "");
      expect(text, relativePath).not.toContain("assets/source/");
    }
  });
});
