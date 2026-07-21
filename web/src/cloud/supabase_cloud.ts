import type { SupabaseClient } from "@supabase/supabase-js";
import type { ValidationReport } from "@mathland/contracts";

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
} from "./cloud_port";

function cloudError(operation: string, error: { message?: string } | null): Error {
  return new Error(`${operation} failed${error?.message ? `: ${error.message}` : ""}`);
}

function asGuardianRole(value: unknown): GuardianRole {
  return value === "owner" || value === "editor" ? value : "guardian";
}

function requireData<T>(operation: string, data: unknown, error: { message?: string } | null): T {
  if (error || data === null || data === undefined) {
    throw cloudError(operation, error);
  }
  return data as T;
}

export class SupabaseCloud implements CloudPort {
  constructor(private readonly client: SupabaseClient) {}

  async session(): Promise<SessionState> {
    const { data, error } = await this.client.auth.getSession();
    if (error) throw cloudError("session", error);
    const user = data.session?.user;
    if (!user) return { status: "signed_out" };
    return {
      status: "authenticated",
      userId: user.id,
      role: asGuardianRole(user.app_metadata?.role),
    };
  }

  async sendMagicLink(email: string, redirectTo: string): Promise<void> {
    const { error } = await this.client.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirectTo, shouldCreateUser: false },
    });
    if (error) throw cloudError("send magic link", error);
  }

  async signOut(): Promise<void> {
    const { error } = await this.client.auth.signOut();
    if (error) throw cloudError("sign out", error);
  }

  async listFamilies(): Promise<FamilySummary[]> {
    const { data, error } = await this.client
      .from("guardian_families")
      .select("id,name,role")
      .order("name");
    return requireData("list families", data, error);
  }

  async listChildren(familyId: string): Promise<ChildSummary[]> {
    const { data, error } = await this.client
      .from("guardian_children")
      .select("id,familyId:family_id,nickname,lastSyncAt:last_sync_at")
      .eq("family_id", familyId)
      .order("nickname");
    return requireData("list children", data, error);
  }

  async dashboard(query: DashboardQuery): Promise<DashboardSnapshot> {
    const { data, error } = await this.client.rpc("guardian_dashboard", {
      p_family_id: query.familyId,
      p_profile_id: query.profileId ?? null,
      p_range: query.range,
    });
    return requireData("load dashboard", data, error);
  }

  async createPairingCode(profileId: string): Promise<PairingCodeResult> {
    return this.invoke("create-pairing-code", { profileId });
  }

  async disconnectDevice(deviceId: string): Promise<void> {
    await this.invoke("disconnect-device", { deviceId });
  }

  async exportFamily(familyId: string): Promise<Blob> {
    const payload = await this.invoke<unknown>("export-family", { familyId });
    return new Blob([JSON.stringify(payload)], { type: "application/json" });
  }

  async deleteProfile(profileId: string, confirmation: string): Promise<void> {
    await this.invoke("delete-profile", { profileId, confirmation });
  }

  async listDrafts(): Promise<ContentDraftSummary[]> {
    const { data, error } = await this.client
      .from("content_drafts")
      .select("id,activityId:activity_id,title,revision,updatedAt:updated_at")
      .order("updated_at", { ascending: false });
    return requireData("list drafts", data, error);
  }

  async loadDraft(draftId: string): Promise<ContentDraft> {
    const { data, error } = await this.client
      .from("content_drafts")
      .select("id,activityId:activity_id,title,revision,updatedAt:updated_at,package")
      .eq("id", draftId)
      .single();
    return requireData("load draft", data, error);
  }

  async saveDraft(input: SaveDraftInput): Promise<ContentDraft> {
    return this.invoke("save-draft", input);
  }

  async validateDraft(draftId: string): Promise<ValidationReport> {
    return this.invoke("validate-draft", { draftId });
  }

  async publishDraft(
    draftId: string,
    expectedRevision: number,
  ): Promise<ContentPublication> {
    return this.invoke("publish-draft", { draftId, expectedRevision });
  }

  async rollbackPublication(
    activityId: string,
    contentVersion: string,
  ): Promise<ContentPublication> {
    return this.invoke("rollback-publication", { activityId, contentVersion });
  }

  async requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult> {
    return this.invoke("request-ai-patch", { draftId, instruction });
  }

  private async invoke<T>(name: string, body: object): Promise<T> {
    const { data, error } = await this.client.functions.invoke(name, {
      body: body as Record<string, unknown>,
    });
    return requireData(name, data, error);
  }
}
