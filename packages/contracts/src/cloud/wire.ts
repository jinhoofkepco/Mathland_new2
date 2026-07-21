import { z } from "zod";

import { ActivityPackageDraftV1Schema, ActivityPackageV1Schema } from "../content/schema.js";

export const CloudUuidSchema = z.uuid();
export const CloudTimestampSchema = z.iso.datetime({ offset: true });
export const GuardianRoleSchema = z.enum(["guardian", "editor", "owner"]);
export type GuardianRole = z.infer<typeof GuardianRoleSchema>;

export const SessionStateSchema = z.discriminatedUnion("status", [
  z.strictObject({ status: z.literal("signed_out") }),
  z.strictObject({ status: z.literal("unauthorized"), userId: CloudUuidSchema }),
  z.strictObject({
    status: z.literal("authenticated"),
    userId: CloudUuidSchema,
    role: GuardianRoleSchema,
  }),
]);
export type SessionState = z.infer<typeof SessionStateSchema>;

export const FamilySummarySchema = z.strictObject({
  id: CloudUuidSchema,
  name: z.string().trim().min(1).max(80),
  role: GuardianRoleSchema,
});
export type FamilySummary = z.infer<typeof FamilySummarySchema>;

export const FamilyMembershipRowSchema = z.strictObject({
  role: GuardianRoleSchema,
  family: z.strictObject({
    id: CloudUuidSchema,
    name: z.string().trim().min(1).max(80),
  }),
});

export const SessionMembershipRowSchema = z.strictObject({ role: GuardianRoleSchema });

export const ChildSummarySchema = z.strictObject({
  id: CloudUuidSchema,
  familyId: CloudUuidSchema,
  nickname: z.string().trim().min(1).max(32),
  lastSyncAt: CloudTimestampSchema.nullable(),
});
export type ChildSummary = z.infer<typeof ChildSummarySchema>;

export const ChildProfileRowSchema = z.strictObject({
  id: CloudUuidSchema,
  family_id: CloudUuidSchema,
  nickname: z.string().trim().min(1).max(32),
  devices: z.array(
    z.strictObject({
      last_sync_at: CloudTimestampSchema.nullable(),
    }),
  ),
});

export const DashboardRangeSchema = z.enum(["7d", "30d", "90d"]);
export type DashboardRange = z.infer<typeof DashboardRangeSchema>;

export const DashboardQuerySchema = z.strictObject({
  familyId: CloudUuidSchema,
  profileId: CloudUuidSchema.optional(),
  range: DashboardRangeSchema,
});
export type DashboardQuery = z.infer<typeof DashboardQuerySchema>;

export const GuardianSessionRowSchema = z.strictObject({
  family_id: CloudUuidSchema,
  profile_id: CloudUuidSchema,
  session_id: z.string().min(1).max(128),
  started_at: CloudTimestampSchema,
  completed_at: CloudTimestampSchema,
  final_score: z.number().int().nonnegative().nullable(),
  final_health: z.number().int().nonnegative().nullable(),
  answer_count: z.number().int().nonnegative(),
  correct_count: z.number().int().nonnegative(),
});

export const GuardianActivityRowSchema = z.strictObject({
  family_id: CloudUuidSchema,
  profile_id: CloudUuidSchema,
  activity_id: z.string().min(1).max(128),
  answer_count: z.number().int().nonnegative(),
  correct_count: z.number().int().nonnegative(),
  average_response_duration_ms: z.number().int().nonnegative(),
  last_played_at: CloudTimestampSchema,
});

export const GuardianErrorPatternRowSchema = z.strictObject({
  family_id: CloudUuidSchema,
  profile_id: CloudUuidSchema,
  activity_id: z.string().min(1).max(128),
  generator_id: z.string().min(1).max(128),
  band_id: z.string().min(1).max(64),
  incorrect_count: z.number().int().nonnegative(),
  last_incorrect_at: CloudTimestampSchema,
});

export const GuardianRewardRowSchema = z.strictObject({
  family_id: CloudUuidSchema,
  profile_id: CloudUuidSchema,
  reward_id: z.string().min(1).max(128),
  quantity: z.number().int().nonnegative(),
  updated_at: CloudTimestampSchema,
});

export const DashboardSessionSummarySchema = z.strictObject({
  runId: z.string().min(1).max(128),
  profileId: CloudUuidSchema,
  startedAt: CloudTimestampSchema,
  score: z.number().int().nonnegative(),
});
export type DashboardSessionSummary = z.infer<typeof DashboardSessionSummarySchema>;

export const DashboardActivitySummarySchema = z.strictObject({
  profileId: CloudUuidSchema,
  activityId: z.string().min(1).max(128),
  answerCount: z.number().int().nonnegative(),
  correctCount: z.number().int().nonnegative(),
  averageResponseDurationMs: z.number().int().nonnegative(),
  lastPlayedAt: CloudTimestampSchema,
});
export type DashboardActivitySummary = z.infer<typeof DashboardActivitySummarySchema>;

export const DashboardErrorPatternSchema = z.strictObject({
  profileId: CloudUuidSchema,
  activityId: z.string().min(1).max(128),
  generatorId: z.string().min(1).max(128),
  bandId: z.string().min(1).max(64),
  incorrectCount: z.number().int().nonnegative(),
  lastIncorrectAt: CloudTimestampSchema,
});
export type DashboardErrorPattern = z.infer<typeof DashboardErrorPatternSchema>;

export const DashboardRewardSummarySchema = z.strictObject({
  profileId: CloudUuidSchema,
  rewardId: z.string().min(1).max(128),
  quantity: z.number().int().nonnegative(),
  updatedAt: CloudTimestampSchema,
});
export type DashboardRewardSummary = z.infer<typeof DashboardRewardSummarySchema>;

export const DashboardSnapshotSchema = z.strictObject({
  familyId: CloudUuidSchema,
  generatedAt: CloudTimestampSchema,
  sessions: z.array(DashboardSessionSummarySchema),
  activities: z.array(DashboardActivitySummarySchema),
  errors: z.array(DashboardErrorPatternSchema),
  rewards: z.array(DashboardRewardSummarySchema),
});
export type DashboardSnapshot = z.infer<typeof DashboardSnapshotSchema>;

export const PairingCodeResultSchema = z.strictObject({
  code: z.string().regex(/^[0-9]{6}$/),
  expiresAt: CloudTimestampSchema,
});
export type PairingCodeResult = z.infer<typeof PairingCodeResultSchema>;

export const GuardianRewardStatusSchema = z.enum([
  "available",
  "claimed",
  "cancelled",
]);
export type GuardianRewardStatus = z.infer<typeof GuardianRewardStatusSchema>;

export const GuardianRewardProjectionRowSchema = z.strictObject({
  id: CloudUuidSchema,
  profile_id: CloudUuidSchema,
  title: z.string().trim().min(1).max(120),
  required_apples: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
  status: GuardianRewardStatusSchema,
  created_at: CloudTimestampSchema,
  claimed_at: CloudTimestampSchema.nullable(),
});
export type GuardianRewardProjectionRow = z.infer<
  typeof GuardianRewardProjectionRowSchema
>;

export const CreateGuardianRewardInputSchema = z.strictObject({
  profileId: CloudUuidSchema,
  title: z.string().trim().min(1).max(120),
  requiredApples: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
});
export type CreateGuardianRewardInput = z.infer<
  typeof CreateGuardianRewardInputSchema
>;

export const UpdateGuardianRewardInputSchema = z.strictObject({
  rewardId: CloudUuidSchema,
  title: z.string().trim().min(1).max(120),
  requiredApples: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
  status: GuardianRewardStatusSchema,
});
export type UpdateGuardianRewardInput = z.infer<
  typeof UpdateGuardianRewardInputSchema
>;

export const DuePublicationBatchLimitSchema = z.number().int().min(1).max(100);
export const PublicationReasonSchema = z.string().max(500).trim().min(1);

export const ContentDraftSummarySchema = z.strictObject({
  id: CloudUuidSchema,
  activityId: z.string().min(1).max(128),
  title: z.string().trim().min(1).max(160),
  revision: z.number().int().positive(),
  updatedAt: CloudTimestampSchema,
});
export type ContentDraftSummary = z.infer<typeof ContentDraftSummarySchema>;

export const ContentDraftSchema = ContentDraftSummarySchema.extend({
  package: ActivityPackageDraftV1Schema,
});
export type ContentDraft = z.infer<typeof ContentDraftSchema>;

export const SaveDraftInputSchema = z.strictObject({
  draftId: CloudUuidSchema.optional(),
  expectedRevision: z.number().int().positive().optional(),
  package: ActivityPackageDraftV1Schema,
});
export type SaveDraftInput = z.infer<typeof SaveDraftInputSchema>;

export const ValidationReportWireSchema = z.strictObject({
  valid: z.boolean(),
  issues: z.array(
    z.strictObject({
      code: z.string().min(1).max(128),
      path: z.array(z.union([z.string(), z.number().int()])),
      message: z.string().min(1).max(500),
    }),
  ),
  samples: z.array(z.record(z.string(), z.unknown())),
});
export type ValidationReportWire = z.infer<typeof ValidationReportWireSchema>;

export const ContentPublicationSchema = z.strictObject({
  activityId: z.string().min(1).max(128),
  contentVersion: z.string().regex(/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/),
  publishedAt: CloudTimestampSchema,
  package: ActivityPackageV1Schema,
});
export type ContentPublication = z.infer<typeof ContentPublicationSchema>;

export const ContentPublicationHistoryItemSchema = z.strictObject({
  id: CloudUuidSchema,
  activityId: z.string().min(1).max(128),
  contentVersion: z.string().regex(/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/),
  checksum: z.string().regex(/^sha256:[0-9a-f]{64}$/),
  status: z.enum(["pending", "active", "retired"]),
  publishedAt: CloudTimestampSchema,
  effectiveAt: CloudTimestampSchema,
  publishedBy: CloudUuidSchema.nullable(),
  sourceRevision: z.number().int().positive(),
  rollbackOfId: CloudUuidSchema.nullable(),
  reason: z.string().trim().min(1).max(500).nullable(),
  validationValid: z.boolean(),
});
export type ContentPublicationHistoryItem = z.infer<typeof ContentPublicationHistoryItemSchema>;

export const AiPatchResultSchema = z.strictObject({
  draftId: CloudUuidSchema,
  baseRevision: z.number().int().positive(),
  patch: z.array(
    z.strictObject({
      op: z.enum(["add", "remove", "replace", "test"]),
      path: z.string().startsWith("/"),
      value: z.unknown().optional(),
    }),
  ),
  provider: z.string().min(1).max(80),
});
export type AiPatchResult = z.infer<typeof AiPatchResultSchema>;

export const FunctionAckSchema = z.strictObject({ ok: z.literal(true) });

export const FamilyExportSchema = z.strictObject({
  schemaVersion: z.literal(1),
  family: FamilySummarySchema,
  children: z.array(ChildSummarySchema),
  exportedAt: CloudTimestampSchema,
});
