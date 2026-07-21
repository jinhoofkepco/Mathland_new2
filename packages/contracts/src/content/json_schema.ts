import { z } from "zod";

import { ActivityPackageV1Schema, ContentManifestV1Schema } from "./schema.js";

export type ContentJsonSchemaFileName =
  | "activity-package-v1.schema.json"
  | "content-manifest-v1.schema.json";
export type JsonSchemaDocument = Record<string, unknown>;

export function generateContentJsonSchemas(): Record<ContentJsonSchemaFileName, JsonSchemaDocument> {
  const activityPackageSchema = decorateSchema(
    z.toJSONSchema(ActivityPackageV1Schema, { target: "draft-2020-12" }),
    "https://mathland.local/schemas/activity-package-v1.schema.json",
    "MathLand Activity Package v1",
    [
      "activity generator matches activity_id",
      "number-theory generators require their registered answer layouts",
      "combo thresholds strictly increase",
      "adaptive bounds reference ordered bands and default off",
      "each band includes validation seeds 1, 7, 42, and 20260721",
      "tuning strings are identifiers, not paths, URLs, or executable code",
      "checksum equals SHA-256 of canonical JSON without the root checksum",
    ],
  );
  closeTuple(activityPackageSchema, ["properties", "run", "properties", "combo_thresholds"], 3);
  closeTuple(activityPackageSchema, ["properties", "difficulty_bands"], 3);

  return {
    "activity-package-v1.schema.json": activityPackageSchema,
    "content-manifest-v1.schema.json": decorateSchema(
      z.toJSONSchema(ContentManifestV1Schema, { target: "draft-2020-12" }),
      "https://mathland.local/schemas/content-manifest-v1.schema.json",
      "MathLand Content Manifest v1",
      [
        "activity_order and package entries contain the complete canonical catalogue",
        "each package path exactly matches its activity_id and content_version",
        "manifest and parsed package checksums match",
      ],
    ),
  };
}

function closeTuple(schema: JsonSchemaDocument, path: readonly string[], length: number): void {
  let node = schema;
  for (const segment of path) {
    const child = node[segment];
    if (child === null || typeof child !== "object" || Array.isArray(child)) {
      throw new TypeError(`Expected JSON Schema object at ${path.join(".")}`);
    }
    node = child as JsonSchemaDocument;
  }
  if (!Array.isArray(node.prefixItems) || node.prefixItems.length !== length) {
    throw new TypeError(`Expected ${length} prefixItems at ${path.join(".")}`);
  }
  node.minItems = length;
  node.maxItems = length;
  node.items = false;
}

export function renderJsonSchema(schema: JsonSchemaDocument): string {
  return `${JSON.stringify(schema, null, 2)}\n`;
}

export async function writeContentJsonSchemas(
  outputDirectory: URL = new URL("./", import.meta.url),
): Promise<void> {
  const { mkdir, writeFile } = await import("node:fs/promises");
  await mkdir(outputDirectory, { recursive: true });
  const schemas = generateContentJsonSchemas();
  await Promise.all(
    Object.entries(schemas).map(([fileName, schema]) =>
      writeFile(new URL(fileName, outputDirectory), renderJsonSchema(schema), "utf8"),
    ),
  );
}

function decorateSchema(
  generated: object,
  id: string,
  title: string,
  semanticRules: readonly string[],
): JsonSchemaDocument {
  const serializable = JSON.parse(JSON.stringify(generated)) as Record<string, unknown>;
  const { $schema, ...body } = serializable;
  return {
    $schema,
    $id: id,
    title,
    $comment: "Cross-field rules are enforced by the exported semantic validators.",
    "x-mathland-semantic-validation": [...semanticRules],
    ...body,
  };
}
