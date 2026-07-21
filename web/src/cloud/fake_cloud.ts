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
  PairingCodeResult,
  SaveDraftInput,
  SessionState,
  ValidationReportWire,
} from "./cloud_port";

export interface FakeCloudDataset {
  session: SessionState;
  families: FamilySummary[];
  children: ChildSummary[];
  dashboards: Record<string, DashboardSnapshot>;
  drafts?: ContentDraft[];
}

const DEFAULT_DATASET: FakeCloudDataset = {
  session: { status: "signed_out" },
  families: [],
  children: [],
  dashboards: {},
  drafts: [],
};

function clone<T>(value: T): T {
  return structuredClone(value);
}

function requireNonBlank(value: string, label: string): string {
  const normalized = value.trim();
  if (normalized === "") {
    throw new Error(`${label} is required`);
  }
  return normalized;
}

export class FakeCloud implements CloudPort {
  #session: SessionState;
  #families: FamilySummary[];
  #children: ChildSummary[];
  readonly #dashboards: Record<string, DashboardSnapshot>;
  #drafts: ContentDraft[];

  constructor(dataset: FakeCloudDataset = DEFAULT_DATASET) {
    const isolated = clone(dataset);
    this.#session = isolated.session;
    this.#families = isolated.families;
    this.#children = isolated.children;
    this.#dashboards = isolated.dashboards;
    this.#drafts = isolated.drafts ?? [];
  }

  async session(): Promise<SessionState> {
    return clone(this.#session);
  }

  async sendMagicLink(email: string, redirectTo: string): Promise<void> {
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      throw new Error("A valid email is required");
    }
    const url = new URL(redirectTo);
    if (!/^https?:$/.test(url.protocol)) {
      throw new Error("A valid redirect URL is required");
    }
  }

  async signOut(): Promise<void> {
    this.#session = { status: "signed_out" };
  }

  async listFamilies(): Promise<FamilySummary[]> {
    return clone(this.#families);
  }

  async listChildren(familyId: string): Promise<ChildSummary[]> {
    return clone(this.#children.filter((child) => child.familyId === familyId));
  }

  async dashboard(query: DashboardQuery): Promise<DashboardSnapshot> {
    const snapshot = this.#dashboards[query.familyId];
    if (!snapshot) {
      throw new Error(`Dashboard is not available for family ${query.familyId}`);
    }
    const copy = clone(snapshot);
    if (query.profileId) {
      copy.sessions = copy.sessions.filter((session) => session.profileId === query.profileId);
      copy.activities = copy.activities.filter((activity) => activity.profileId === query.profileId);
      copy.errors = copy.errors.filter((error) => error.profileId === query.profileId);
      copy.rewards = copy.rewards.filter((reward) => reward.profileId === query.profileId);
    }
    return copy;
  }

  async createPairingCode(profileId: string): Promise<PairingCodeResult> {
    if (!this.#children.some((child) => child.id === profileId)) {
      throw new Error("Profile is not available");
    }
    return { code: "482913", expiresAt: new Date(Date.now() + 10 * 60_000).toISOString() };
  }

  async disconnectDevice(deviceId: string): Promise<void> {
    requireNonBlank(deviceId, "deviceId");
  }

  async exportFamily(familyId: string): Promise<Blob> {
    const family = this.#families.find((candidate) => candidate.id === familyId);
    if (!family) {
      throw new Error("Family is not available");
    }
    return new Blob(
      [
        JSON.stringify({
          family,
          children: this.#children.filter((child) => child.familyId === familyId),
        }),
      ],
      { type: "application/json" },
    );
  }

  async deleteProfile(profileId: string, confirmation: string): Promise<void> {
    const profile = this.#children.find((child) => child.id === profileId);
    if (!profile || confirmation !== profile.nickname) {
      throw new Error("Profile confirmation does not match");
    }
    this.#children = this.#children.filter((child) => child.id !== profileId);
  }

  async listDrafts(): Promise<ContentDraftSummary[]> {
    return clone(
      this.#drafts.map(({ package: _package, ...summary }) => summary),
    );
  }

  async loadDraft(draftId: string): Promise<ContentDraft> {
    const draft = this.#drafts.find((candidate) => candidate.id === draftId);
    if (!draft) {
      throw new Error("Draft is not available");
    }
    return clone(draft);
  }

  async saveDraft(input: SaveDraftInput): Promise<ContentDraft> {
    const existing = input.draftId
      ? this.#drafts.find((candidate) => candidate.id === input.draftId)
      : undefined;
    if (existing && input.expectedRevision !== existing.revision) {
      throw new Error("Draft revision conflict");
    }
    const next: ContentDraft = {
      id: existing?.id ?? `draft-${this.#drafts.length + 1}`,
      activityId: input.package.activity_id,
      title: input.package.localizations["ko-KR"].title,
      revision: (existing?.revision ?? 0) + 1,
      updatedAt: "2030-01-01T00:00:00.000Z",
      package: clone(input.package),
    };
    this.#drafts = [...this.#drafts.filter((draft) => draft.id !== next.id), next];
    return clone(next);
  }

  async validateDraft(draftId: string, _packageDraft?: ContentDraft["package"]): Promise<ValidationReportWire> {
    await this.loadDraft(draftId);
    return { valid: true, issues: [], samples: [] };
  }

  async publishDraft(
    _draftId: string,
    _expectedRevision: number,
  ): Promise<ContentPublication> {
    throw new Error("Fake publication fixture is not configured");
  }

  async rollbackPublication(
    _activityId: string,
    _contentVersion: string,
  ): Promise<ContentPublication> {
    throw new Error("Fake rollback fixture is not configured");
  }

  async requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult> {
    const draft = await this.loadDraft(draftId);
    requireNonBlank(instruction, "instruction");
    return {
      draftId,
      baseRevision: draft.revision,
      patch: [],
      provider: "fake-disabled",
    };
  }
}

export function createDemoFakeCloud(): FakeCloud {
  return new FakeCloud(DEFAULT_DATASET);
}
