import type {
  AiPatchResult,
  BootstrapGuardianOnboardingInput,
  BootstrapGuardianOnboardingResult,
  ChildSummary,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  ContentPublicationHistoryItem,
  DashboardRange,
  DashboardQuery,
  DashboardSnapshot,
  FamilySummary,
  GuardianFamilyStatus,
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "@mathland/contracts/cloud";

export type {
  AiPatchResult,
  BootstrapGuardianOnboardingInput,
  BootstrapGuardianOnboardingResult,
  ChildSummary,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  ContentPublicationHistoryItem,
  DashboardRange,
  DashboardQuery,
  DashboardSnapshot,
  FamilySummary,
  GuardianFamilyStatus,
  GuardianRole,
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "@mathland/contracts/cloud";

export interface CloudPort {
  session(): Promise<SessionState>;
  sendMagicLink(email: string, redirectTo: string): Promise<void>;
  bootstrapGuardian(
    input: BootstrapGuardianOnboardingInput,
  ): Promise<BootstrapGuardianOnboardingResult>;
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
  validateDraft(draftId: string, packageDraft?: ContentDraft["package"]): Promise<ValidationReportWire>;
  publishDraft(
    draftId: string,
    expectedRevision: number,
    options?: { effectiveAt?: string; reason?: string },
  ): Promise<ContentPublication>;
  listPublicationHistory(activityId?: string): Promise<ContentPublicationHistoryItem[]>;
  rollbackPublication(publicationId: string, reason: string): Promise<ContentPublication>;
  requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult>;
}
