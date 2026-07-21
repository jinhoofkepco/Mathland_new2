import type {
  AiPatchResult,
  ChildSummary,
  CloudPort,
  ContentDraft,
  ContentDraftSummary,
  ContentPublication,
  ContentPublicationHistoryItem,
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
  publications?: ContentPublicationHistoryItem[];
}

const DEFAULT_DATASET: FakeCloudDataset = {
  session: { status: "signed_out" },
  families: [],
  children: [],
  dashboards: {},
  drafts: [],
};

const DEMO_FAMILY_ID = "00000000-0000-4000-8000-000000000001";
const DEMO_CHILD_ID = "00000000-0000-4000-8000-000000000002";
const DEMO_USER_ID = "00000000-0000-4000-8000-000000000003";
const DEMO_SYNC_AT = "2026-07-21T09:20:00.000Z";

const DEMO_DATASET: FakeCloudDataset = {
  session: { status: "authenticated", userId: DEMO_USER_ID, role: "owner" },
  families: [{ id: DEMO_FAMILY_ID, name: "MathLand 데모 가족", role: "owner" }],
  children: [
    {
      id: DEMO_CHILD_ID,
      familyId: DEMO_FAMILY_ID,
      nickname: "데모 아이",
      lastSyncAt: DEMO_SYNC_AT,
    },
  ],
  dashboards: {
    [DEMO_FAMILY_ID]: {
      familyId: DEMO_FAMILY_ID,
      generatedAt: "2026-07-21T09:21:00.000Z",
      sessions: [
        {
          runId: "demo-run-1",
          profileId: DEMO_CHILD_ID,
          startedAt: "2026-07-21T09:00:00.000Z",
          score: 8,
        },
        {
          runId: "demo-run-2",
          profileId: DEMO_CHILD_ID,
          startedAt: "2026-07-20T08:30:00.000Z",
          score: 6,
        },
      ],
      activities: [
        {
          profileId: DEMO_CHILD_ID,
          activityId: "foundations_base_ten",
          answerCount: 12,
          correctCount: 10,
          averageResponseDurationMs: 3200,
          lastPlayedAt: DEMO_SYNC_AT,
        },
        {
          profileId: DEMO_CHILD_ID,
          activityId: "addition_ones",
          answerCount: 8,
          correctCount: 6,
          averageResponseDurationMs: 4100,
          lastPlayedAt: "2026-07-20T08:45:00.000Z",
        },
      ],
      errors: [
        {
          profileId: DEMO_CHILD_ID,
          activityId: "addition_ones",
          generatorId: "addition_v1",
          bandId: "practice",
          incorrectCount: 2,
          lastIncorrectAt: "2026-07-20T08:43:00.000Z",
        },
      ],
      rewards: [
        {
          profileId: DEMO_CHILD_ID,
          rewardId: "apple",
          quantity: 14,
          updatedAt: DEMO_SYNC_AT,
        },
      ],
    },
  },
  drafts: [],
  publications: [],
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
  #publications: ContentPublicationHistoryItem[];

  constructor(dataset: FakeCloudDataset = DEFAULT_DATASET) {
    const isolated = clone(dataset);
    this.#session = isolated.session;
    this.#families = isolated.families;
    this.#children = isolated.children;
    this.#dashboards = isolated.dashboards;
    this.#drafts = isolated.drafts ?? [];
    this.#publications = isolated.publications ?? [];
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
    draftId: string,
    expectedRevision: number,
    options: { effectiveAt?: string; reason?: string } = {},
  ): Promise<ContentPublication> {
    if (this.#session.status !== "authenticated" || this.#session.role !== "owner") throw new Error("Owner role is required");
    const draft = await this.loadDraft(draftId);
    if (draft.revision !== expectedRevision) throw new Error("Draft revision conflict");
    const checksum = `sha256:${"0".repeat(64)}` as const;
    const now = "2030-01-01T00:00:00.000Z";
    const effectiveAt = options.effectiveAt ?? now;
    const id = `40000000-0000-4000-8000-${String(this.#publications.length + 1).padStart(12, "0")}`;
    this.#publications = this.#publications.map((item) =>
      item.activityId === draft.activityId && item.status === "active"
        ? { ...item, status: "retired" }
        : item,
    );
    this.#publications.push({
      id,
      activityId: draft.activityId,
      contentVersion: draft.package.content_version,
      checksum,
      status: effectiveAt > now ? "pending" : "active",
      publishedAt: now,
      effectiveAt,
      publishedBy: this.#session.status === "authenticated" ? this.#session.userId : null,
      sourceRevision: draft.revision,
      rollbackOfId: null,
      reason: options.reason?.trim() || null,
      validationValid: true,
    });
    return {
      activityId: draft.activityId,
      contentVersion: draft.package.content_version,
      publishedAt: now,
      package: { ...clone(draft.package), checksum },
    };
  }

  async listPublicationHistory(activityId?: string): Promise<ContentPublicationHistoryItem[]> {
    return clone(this.#publications.filter((item) => !activityId || item.activityId === activityId));
  }

  async rollbackPublication(publicationId: string, reason: string): Promise<ContentPublication> {
    if (this.#session.status !== "authenticated" || this.#session.role !== "owner") throw new Error("Owner role is required");
    const historical = this.#publications.find((item) => item.id === publicationId && item.status === "retired");
    if (!historical) throw new Error("Historical publication is not available");
    const draft = this.#drafts.find((item) => item.activityId === historical.activityId);
    if (!draft) throw new Error("Draft is not available");
    const now = "2030-01-01T00:00:00.000Z";
    this.#publications = this.#publications.map((item) => item.activityId === historical.activityId && item.status === "active" ? { ...item, status: "retired" } : item);
    this.#publications.push({ ...historical, id: `40000000-0000-4000-8000-${String(this.#publications.length + 1).padStart(12, "0")}`, status: "active", publishedAt: now, effectiveAt: now, rollbackOfId: historical.id, reason: requireNonBlank(reason, "reason") });
    return {
      activityId: historical.activityId,
      contentVersion: historical.contentVersion,
      publishedAt: now,
      package: { ...clone(draft.package), content_version: historical.contentVersion, checksum: historical.checksum },
    };
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
  return new FakeCloud(DEMO_DATASET);
}
