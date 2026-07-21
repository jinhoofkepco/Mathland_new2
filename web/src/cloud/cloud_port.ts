import type {
  ActivityPackageDraftV1,
  ActivityPackageV1,
  ValidationReport,
} from "@mathland/contracts";

export type GuardianRole = "guardian" | "editor" | "owner";

export type SessionState =
  | { status: "signed_out" }
  | { status: "authenticated"; userId: string; role: GuardianRole };

export interface FamilySummary {
  id: string;
  name: string;
  role: GuardianRole;
}

export interface ChildSummary {
  id: string;
  familyId: string;
  nickname: string;
  lastSyncAt: string | null;
}

export type DashboardRange = "7d" | "30d" | "90d";

export interface DashboardQuery {
  familyId: string;
  profileId?: string;
  range: DashboardRange;
}

export interface DashboardSessionSummary {
  runId: string;
  profileId: string;
  startedAt: string;
  score: number;
}

export interface DashboardSnapshot {
  familyId: string;
  generatedAt: string;
  sessions: DashboardSessionSummary[];
}

export interface PairingCodeResult {
  code: string;
  expiresAt: string;
}

export interface ContentDraftSummary {
  id: string;
  activityId: string;
  title: string;
  revision: number;
  updatedAt: string;
}

export interface ContentDraft extends ContentDraftSummary {
  package: ActivityPackageDraftV1;
}

export interface SaveDraftInput {
  draftId?: string;
  expectedRevision?: number;
  package: ActivityPackageDraftV1;
}

export interface ContentPublication {
  activityId: string;
  contentVersion: string;
  publishedAt: string;
  package: ActivityPackageV1;
}

export interface AiPatchResult {
  draftId: string;
  baseRevision: number;
  patch: readonly Record<string, unknown>[];
  provider: string;
}

export interface CloudPort {
  session(): Promise<SessionState>;
  sendMagicLink(email: string, redirectTo: string): Promise<void>;
  signOut(): Promise<void>;
  listFamilies(): Promise<FamilySummary[]>;
  listChildren(familyId: string): Promise<ChildSummary[]>;
  dashboard(query: DashboardQuery): Promise<DashboardSnapshot>;
  createPairingCode(profileId: string): Promise<PairingCodeResult>;
  disconnectDevice(deviceId: string): Promise<void>;
  exportFamily(familyId: string): Promise<Blob>;
  deleteProfile(profileId: string, confirmation: string): Promise<void>;
  listDrafts(): Promise<ContentDraftSummary[]>;
  loadDraft(draftId: string): Promise<ContentDraft>;
  saveDraft(input: SaveDraftInput): Promise<ContentDraft>;
  validateDraft(draftId: string): Promise<ValidationReport>;
  publishDraft(draftId: string, expectedRevision: number): Promise<ContentPublication>;
  rollbackPublication(
    activityId: string,
    contentVersion: string,
  ): Promise<ContentPublication>;
  requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult>;
}
