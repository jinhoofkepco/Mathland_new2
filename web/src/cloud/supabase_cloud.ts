import type { SupabaseClient } from "@supabase/supabase-js";
import { z, type ZodType } from "zod";
import {
  AiPatchResultSchema,
  ChildProfileRowSchema,
  ChildSummarySchema,
  CloudUuidSchema,
  ContentDraftSchema,
  ContentDraftSummarySchema,
  ContentPublicationSchema,
  DashboardQuerySchema,
  DashboardSnapshotSchema,
  FamilyExportSchema,
  FamilyMembershipRowSchema,
  FamilySummarySchema,
  FunctionAckSchema,
  GuardianActivityRowSchema,
  GuardianErrorPatternRowSchema,
  GuardianRewardRowSchema,
  GuardianSessionRowSchema,
  PairingCodeResultSchema,
  SessionMembershipRowSchema,
  SessionStateSchema,
  ValidationReportWireSchema,
} from "@mathland/contracts/cloud";

import type {
  AiPatchResult,
  ChildSummary,
  CloudPort,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  DashboardQuery,
  DashboardSnapshot,
  FamilySummary,
  GuardianRole,
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "./cloud_port";

type CloudErrorValue = { message?: string } | null;

function cloudError(operation: string, detail?: string): Error {
  return new Error(`${operation} failed${detail ? `: ${detail}` : ""}`);
}

function ensureNoError(operation: string, error: CloudErrorValue): void {
  if (error) throw cloudError(operation, error.message);
}

function parseWire<T>(schema: ZodType<T>, value: unknown, operation: string): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    throw cloudError(operation, result.error.issues[0]?.message ?? "invalid response");
  }
  return result.data;
}

function newestTimestamp(values: Array<string | null>): string | null {
  return values.reduce<string | null>((latest, value) => {
    if (value === null) return latest;
    return latest === null || value > latest ? value : latest;
  }, null);
}

function rangeStart(range: DashboardQuery["range"], now = new Date()): string {
  const days = range === "7d" ? 7 : range === "30d" ? 30 : 90;
  return new Date(now.getTime() - days * 86_400_000).toISOString();
}

function selectRole(roles: GuardianRole[]): GuardianRole | null {
  if (roles.includes("owner")) return "owner";
  if (roles.includes("guardian")) return "guardian";
  if (roles.includes("editor")) return "editor";
  return null;
}

export class SupabaseCloud implements CloudPort {
  constructor(private readonly client: SupabaseClient) {}

  async session(): Promise<SessionState> {
    const { data, error } = await this.client.auth.getSession();
    ensureNoError("session", error);
    const user = data.session?.user;
    if (!user) return { status: "signed_out" };

    const membershipResult = await this.client
      .from("family_memberships")
      .select("role")
      .eq("user_id", user.id)
      .eq("is_active", true);
    ensureNoError("session membership", membershipResult.error);
    const memberships = parseWire(
      z.array(SessionMembershipRowSchema),
      membershipResult.data,
      "session membership",
    );
    let role = selectRole(memberships.map((membership) => membership.role));

    if (!role) {
      const [owner, editor] = await Promise.all([
        this.client.rpc("has_role", { required_role: "owner" }),
        this.client.rpc("has_role", { required_role: "editor" }),
      ]);
      ensureNoError("owner role check", owner.error);
      ensureNoError("editor role check", editor.error);
      role = owner.data === true ? "owner" : editor.data === true ? "editor" : null;
    }

    return parseWire(
      SessionStateSchema,
      role
        ? { status: "authenticated", userId: user.id, role }
        : { status: "unauthorized", userId: user.id },
      "session",
    );
  }

  async sendMagicLink(email: string, redirectTo: string): Promise<void> {
    const { error } = await this.client.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirectTo, shouldCreateUser: false },
    });
    ensureNoError("send magic link", error);
  }

  async signOut(): Promise<void> {
    const { error } = await this.client.auth.signOut();
    ensureNoError("sign out", error);
  }

  async listFamilies(): Promise<FamilySummary[]> {
    const { data, error } = await this.client
      .from("family_memberships")
      .select("role,family:families!inner(id,name)")
      .eq("is_active", true)
      .order("created_at");
    ensureNoError("list families", error);
    const rows = parseWire(z.array(FamilyMembershipRowSchema), data, "list families");
    return rows.map((row) =>
      parseWire(
        FamilySummarySchema,
        { id: row.family.id, name: row.family.name, role: row.role },
        "list families",
      ),
    );
  }

  async listChildren(familyId: string): Promise<ChildSummary[]> {
    const requestedFamily = parseWire(CloudUuidSchema, familyId, "list children family");
    const { data, error } = await this.client
      .from("child_profiles")
      .select("id,family_id,nickname,devices(last_sync_at)")
      .eq("family_id", requestedFamily)
      .is("deleted_at", null)
      .order("nickname");
    ensureNoError("list children", error);
    const rows = parseWire(z.array(ChildProfileRowSchema), data, "list children");
    return rows.map((row) => {
      if (row.family_id !== requestedFamily) {
        throw cloudError("list children", "cross-family response");
      }
      return parseWire(
        ChildSummarySchema,
        {
          id: row.id,
          familyId: row.family_id,
          nickname: row.nickname,
          lastSyncAt: newestTimestamp(row.devices.map((device) => device.last_sync_at)),
        },
        "list children",
      );
    });
  }

  async dashboard(rawQuery: DashboardQuery): Promise<DashboardSnapshot> {
    const query = parseWire(DashboardQuerySchema, rawQuery, "load dashboard query");
    const since = rangeStart(query.range);
    const sessionQuery = this.scopedView(
      "guardian_session_summary",
      query,
      "started_at",
      since,
    );
    const activityQuery = this.scopedView(
      "guardian_activity_summary",
      query,
      "last_played_at",
      since,
    );
    const errorQuery = this.scopedView(
      "guardian_error_patterns",
      query,
      "last_incorrect_at",
      since,
    );
    const rewardQuery = this.scopedView("guardian_reward_summary", query, "updated_at");
    const [sessionResult, activityResult, errorResult, rewardResult] = await Promise.all([
      sessionQuery,
      activityQuery,
      errorQuery,
      rewardQuery,
    ]);
    for (const [operation, result] of [
      ["load session summary", sessionResult],
      ["load activity summary", activityResult],
      ["load error patterns", errorResult],
      ["load reward summary", rewardResult],
    ] as const) {
      ensureNoError(operation, result.error);
    }

    const sessions = parseWire(
      z.array(GuardianSessionRowSchema),
      sessionResult.data,
      "load session summary",
    );
    const activities = parseWire(
      z.array(GuardianActivityRowSchema),
      activityResult.data,
      "load activity summary",
    );
    const errors = parseWire(
      z.array(GuardianErrorPatternRowSchema),
      errorResult.data,
      "load error patterns",
    );
    const rewards = parseWire(
      z.array(GuardianRewardRowSchema),
      rewardResult.data,
      "load reward summary",
    );
    for (const row of [...sessions, ...activities, ...errors, ...rewards]) {
      if (row.family_id !== query.familyId) {
        throw cloudError("load dashboard", "cross-family response");
      }
    }

    return parseWire(
      DashboardSnapshotSchema,
      {
        familyId: query.familyId,
        generatedAt: new Date().toISOString(),
        sessions: sessions.map((row) => ({
          runId: row.session_id,
          profileId: row.profile_id,
          startedAt: row.started_at,
          score: row.final_score ?? 0,
        })),
        activities: activities.map((row) => ({
          profileId: row.profile_id,
          activityId: row.activity_id,
          answerCount: row.answer_count,
          correctCount: row.correct_count,
          averageResponseDurationMs: row.average_response_duration_ms,
          lastPlayedAt: row.last_played_at,
        })),
        errors: errors.map((row) => ({
          profileId: row.profile_id,
          activityId: row.activity_id,
          generatorId: row.generator_id,
          bandId: row.band_id,
          incorrectCount: row.incorrect_count,
          lastIncorrectAt: row.last_incorrect_at,
        })),
        rewards: rewards.map((row) => ({
          profileId: row.profile_id,
          rewardId: row.reward_id,
          quantity: row.quantity,
          updatedAt: row.updated_at,
        })),
      },
      "load dashboard",
    );
  }

  async createPairingCode(profileId: string): Promise<PairingCodeResult> {
    return this.invoke("create-pairing-code", { profileId }, PairingCodeResultSchema);
  }

  async disconnectDevice(deviceId: string): Promise<void> {
    await this.invoke("disconnect-device", { deviceId }, FunctionAckSchema);
  }

  async exportFamily(familyId: string): Promise<Blob> {
    const payload = await this.invoke("export-family", { familyId }, FamilyExportSchema);
    return new Blob([JSON.stringify(payload)], { type: "application/json" });
  }

  async deleteProfile(profileId: string, confirmation: string): Promise<void> {
    await this.invoke("delete-profile", { profileId, confirmation }, FunctionAckSchema);
  }

  async listDrafts(): Promise<ContentDraftSummary[]> {
    const { data, error } = await this.client
      .from("content_drafts")
      .select("id,activityId:activity_id,title,revision,updatedAt:updated_at")
      .order("updated_at", { ascending: false });
    ensureNoError("list drafts", error);
    return parseWire(z.array(ContentDraftSummarySchema), data, "list drafts");
  }

  async loadDraft(draftId: string): Promise<ContentDraft> {
    const { data, error } = await this.client
      .from("content_drafts")
      .select("id,activityId:activity_id,title,revision,updatedAt:updated_at,package")
      .eq("id", draftId)
      .single();
    ensureNoError("load draft", error);
    return parseWire(ContentDraftSchema, data, "load draft");
  }

  async saveDraft(input: SaveDraftInput): Promise<ContentDraft> {
    return this.invoke("save-draft", input, ContentDraftSchema);
  }

  async validateDraft(
    draftId: string,
    packageDraft?: ContentDraft["package"],
  ): Promise<ValidationReportWire> {
    return this.invoke(
      "validate-draft",
      packageDraft ? { draftId, package: packageDraft } : { draftId },
      ValidationReportWireSchema,
    );
  }

  async publishDraft(
    draftId: string,
    expectedRevision: number,
  ): Promise<ContentPublication> {
    return this.invoke(
      "publish-draft",
      { draftId, expectedRevision },
      ContentPublicationSchema,
    );
  }

  async rollbackPublication(
    activityId: string,
    contentVersion: string,
  ): Promise<ContentPublication> {
    return this.invoke(
      "rollback-publication",
      { activityId, contentVersion },
      ContentPublicationSchema,
    );
  }

  async requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult> {
    return this.invoke("request-ai-patch", { draftId, instruction }, AiPatchResultSchema);
  }

  private scopedView(
    table: string,
    query: DashboardQuery,
    orderColumn: string,
    since?: string,
  ) {
    let builder = this.client
      .from(table)
      .select("*")
      .eq("family_id", query.familyId);
    if (query.profileId) builder = builder.eq("profile_id", query.profileId);
    if (since) builder = builder.gte(orderColumn, since);
    return builder.order(orderColumn, { ascending: false });
  }

  private async invoke<T>(
    name: string,
    body: object,
    schema: ZodType<T>,
  ): Promise<T> {
    const { data, error } = await this.client.functions.invoke(name, {
      body: body as Record<string, unknown>,
    });
    ensureNoError(name, error);
    return parseWire(schema, data, name);
  }
}
