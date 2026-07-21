import { readFileSync } from "node:fs";

import {
  ACTIVITY_IDS,
  type ActivityId,
  type ActivityPackageDraftV1,
  type ActivityPackageV1,
  type ContentManifestV1,
  contentChecksum,
} from "../../src/index.js";

export function makeValidDraft(activityId: ActivityId = "addition_ones"): ActivityPackageDraftV1 {
  const sourceUrl = new URL(`../../../../content/sources/${activityId}.json`, import.meta.url);
  return JSON.parse(readFileSync(sourceUrl, "utf8")) as ActivityPackageDraftV1;
}

export function makePublished(
  draft: ActivityPackageDraftV1 = makeValidDraft(),
): ActivityPackageV1 {
  return { ...draft, checksum: contentChecksum(draft) };
}

export function makeAllPublishedPackages(): ActivityPackageV1[] {
  return ACTIVITY_IDS.map((activityId) => makePublished(makeValidDraft(activityId)));
}

export function makeValidManifest(packages: readonly ActivityPackageV1[]): ContentManifestV1 {
  return {
    schema_version: 1,
    manifest_version: "1.0.0",
    published_at: "2026-07-21T00:00:00Z",
    activity_order: [...ACTIVITY_IDS],
    packages: packages.map((activityPackage) => ({
      activity_id: activityPackage.activity_id,
      content_version: activityPackage.content_version,
      path: `content/packages/${activityPackage.activity_id}/${activityPackage.content_version}.json`,
      checksum: activityPackage.checksum,
    })),
  };
}
