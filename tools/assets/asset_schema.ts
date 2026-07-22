import { z } from "zod";

export const MATHLAND_PALETTE = [
  "#66D3B5",
  "#76C8F0",
  "#F4D9A4",
  "#FF8A7A",
  "#E94B4B",
  "#F6C453",
  "#23415A",
  "#FFF8E8",
] as const;

export const REQUIRED_RELEASE_SVGS = [
  "assets/ui/icons/activities/addition_ones.svg",
  "assets/ui/icons/activities/subtraction_ones.svg",
  "assets/ui/icons/activities/multiplication.svg",
  "assets/ui/icons/activities/common_multiples_lcm.svg",
  "assets/ui/icons/activities/prime_factorization.svg",
  "assets/ui/icons/activities/foundations_counting.svg",
  "assets/ui/icons/activities/foundations_number_bonds.svg",
  "assets/ui/icons/activities/foundations_ten_frame.svg",
  "assets/ui/icons/activities/foundations_base_ten.svg",
  "assets/ui/icons/activities/foundations_number_line.svg",
  "assets/ui/icons/activities/foundations_basic_operations.svg",
  "assets/ui/icons/status/correct.svg",
  "assets/ui/icons/status/wrong.svg",
  "assets/ui/icons/status/heart.svg",
  "assets/ui/icons/status/speaker.svg",
  "assets/ui/learning/ten_frame.svg",
  "assets/ui/learning/ten_rod.svg",
  "assets/ui/learning/unit_cube.svg",
  "assets/ui/learning/number_line_marker.svg",
] as const;

export const VisualAssetReviewSchema = z
  .object({
    math_correct: z.boolean(),
    text_absent: z.boolean(),
    transparency_correct: z.boolean(),
    artifacts_absent: z.boolean(),
    child_appropriate: z.boolean(),
    silhouette_clear: z.boolean(),
    contrast_checked: z.boolean(),
    legible_48dp: z.boolean(),
  })
  .strict();

export const AssetReviewSchema = VisualAssetReviewSchema;

export const AudioAssetReviewSchema = z
  .object({
    technical_checked: z.boolean(),
    content_checked: z.boolean(),
    child_appropriate: z.boolean(),
    rights_checked: z.boolean(),
    clipping_absent: z.boolean(),
    release_playback_checked: z.boolean(),
  })
  .strict();

export const AudioFormatSchema = z
  .object({
    container: z.string().trim().min(1).max(32),
    codec: z.string().trim().min(1).max(64),
    sample_rate_hz: z.number().int().positive().max(192_000),
    channels: z.number().int().min(1).max(2),
  })
  .strict();

export const RasterTransformationSchema = z
  .object({
    source_width: z.number().int().positive().max(8192),
    source_height: z.number().int().positive().max(8192),
    output_width: z.number().int().positive().max(8192),
    output_height: z.number().int().positive().max(8192),
    operations: z
      .array(
        z.enum([
          "remove-chroma-key",
          "despill",
          "convert-rgba",
          "resize-lanczos",
          "pad-transparent",
          "optimize-png",
          "add-srgb-chunk",
        ]),
      )
      .min(1),
  })
  .strict();

export const ExternalModelSchema = z
  .object({
    url: z.string().url().max(400),
    revision: z.string().regex(/^[a-f0-9]{40}$/),
    license: z.string().trim().min(1).max(96),
  })
  .strict();

export const AssetRecordSchema = z
  .object({
    id: z.string().regex(/^[a-z][a-z0-9._-]{2,95}$/),
    path: z.string().min(1).max(240),
    kind: z.enum(["svg", "png", "audio", "prompt"]),
    release: z.boolean(),
    width: z.number().int().positive().max(8192).optional(),
    height: z.number().int().positive().max(8192).optional(),
    view_box: z.string().min(1).max(64).optional(),
    alpha: z.enum(["vector", "transparent-corners", "opaque", "source"]).optional(),
    audio_format: AudioFormatSchema.optional(),
    origin: z.enum(["original", "generated-derived", "synthetic-derived", "third-party"]),
    creator: z.string().trim().min(1).max(160),
    tool: z.string().trim().min(1).max(160),
    source_path: z.string().min(1).max(240),
    master_path: z.string().min(1).max(240).optional(),
    prompt_path: z.string().min(1).max(240).optional(),
    prompt_sha256: z.string().regex(/^[a-f0-9]{64}$/).optional(),
    generation_date: z.iso.date().optional(),
    transformation: RasterTransformationSchema.optional(),
    generation_script: z.string().min(1).max(240).optional(),
    input_path: z.string().min(1).max(240).optional(),
    external_model: ExternalModelSchema.optional(),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    license: z.string().trim().min(1).max(96),
    modifications: z.string().trim().min(1).max(500),
    redistribution: z.enum(["confirmed", "unconfirmed"]),
    reviewer: z.string().trim().min(1).max(160),
    review_date: z.iso.date(),
    review: z.union([VisualAssetReviewSchema, AudioAssetReviewSchema]),
  })
  .strict()
  .superRefine((asset, context) => {
    if (asset.kind === "svg") {
      for (const field of ["width", "height", "view_box"] as const) {
        if (asset[field] === undefined) {
          context.addIssue({ code: "custom", path: [field], message: `${field} is required for SVG` });
        }
      }
      if (asset.alpha !== "vector") {
        context.addIssue({ code: "custom", path: ["alpha"], message: "SVG alpha must be vector" });
      }
    }
    if (asset.kind === "png") {
      if (asset.width === undefined || asset.height === undefined) {
        context.addIssue({ code: "custom", path: ["width"], message: "PNG dimensions are required" });
      }
      if (!asset.alpha || asset.alpha === "vector") {
        context.addIssue({ code: "custom", path: ["alpha"], message: "PNG alpha rule is required" });
      }
    }
    if (asset.kind === "audio" && asset.audio_format === undefined) {
      context.addIssue({
        code: "custom",
        path: ["audio_format"],
        message: "Audio technical format is required",
      });
    }
    if (asset.kind === "audio" && !AudioAssetReviewSchema.safeParse(asset.review).success) {
      context.addIssue({
        code: "custom",
        path: ["review"],
        message: "Audio requires the audio-specific technical/content/rights review",
      });
    }
    if (asset.kind !== "audio" && !VisualAssetReviewSchema.safeParse(asset.review).success) {
      context.addIssue({
        code: "custom",
        path: ["review"],
        message: "Visual and prompt assets require the visual review fields",
      });
    }
    if (asset.origin === "generated-derived" && asset.prompt_path === undefined) {
      context.addIssue({
        code: "custom",
        path: ["prompt_path"],
        message: "Generated assets require the exact saved prompt path",
      });
    }
    if (asset.origin === "generated-derived" && asset.prompt_sha256 === undefined) {
      context.addIssue({
        code: "custom",
        path: ["prompt_sha256"],
        message: "Generated assets require the saved prompt SHA-256",
      });
    }
    if (asset.origin === "generated-derived" && asset.generation_date === undefined) {
      context.addIssue({
        code: "custom",
        path: ["generation_date"],
        message: "Generated assets require the generation date",
      });
    }
    if (asset.release && asset.origin === "generated-derived" && asset.master_path === undefined) {
      context.addIssue({
        code: "custom",
        path: ["master_path"],
        message: "Generated-derived releases require a production master path",
      });
    }
    if (
      asset.kind === "png" &&
      asset.release &&
      asset.origin === "generated-derived" &&
      asset.transformation === undefined
    ) {
      context.addIssue({
        code: "custom",
        path: ["transformation"],
        message: "Generated-derived release PNGs require an exact transformation declaration",
      });
    }
    if (asset.origin === "synthetic-derived") {
      if (asset.kind !== "audio") {
        context.addIssue({ code: "custom", path: ["origin"], message: "Synthetic-derived is reserved for audio" });
      }
      for (const field of ["generation_script", "input_path", "external_model"] as const) {
        if (asset[field] === undefined) {
          context.addIssue({ code: "custom", path: [field], message: `${field} is required for synthetic-derived audio` });
        }
      }
    } else if (asset.generation_script !== undefined || asset.input_path !== undefined || asset.external_model !== undefined) {
      context.addIssue({
        code: "custom",
        path: ["origin"],
        message: "Synthetic model provenance fields require synthetic-derived origin",
      });
    }
  });

export const AssetManifestSchema = z
  .object({
    manifest_version: z.literal("1.0.0"),
    generated_at: z.iso.date(),
    palette: z.array(z.string().regex(/^#[A-F0-9]{6}$/)).length(MATHLAND_PALETTE.length),
    assets: z.array(AssetRecordSchema).min(1),
  })
  .strict();

export type AssetReview = z.infer<typeof AssetReviewSchema>;
export type AudioAssetReview = z.infer<typeof AudioAssetReviewSchema>;
export type AssetRecord = z.infer<typeof AssetRecordSchema>;
export type AssetManifest = z.infer<typeof AssetManifestSchema>;

export interface AssetIssue {
  readonly code: string;
  readonly path: readonly (string | number)[];
  readonly message: string;
}

export interface AssetReport {
  readonly ok: boolean;
  readonly issues: readonly AssetIssue[];
}
