import type {
  AiPatchResult,
  ChildSummary,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  DashboardRange,
  DashboardQuery,
  DashboardSnapshot,
  FamilySummary,
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "@mathland/contracts/cloud";

export type {
  AiPatchResult,
  ChildSummary,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  DashboardRange,
  DashboardQuery,
  DashboardSnapshot,
  FamilySummary,
  GuardianRole,
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "@mathland/contracts/cloud";

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
  validateDraft(draftId: string): Promise<ValidationReportWire>;
  publishDraft(draftId: string, expectedRevision: number): Promise<ContentPublication>;
  rollbackPublication(
    activityId: string,
    contentVersion: string,
  ): Promise<ContentPublication>;
  requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult>;
}
