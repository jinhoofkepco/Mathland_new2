import type { LearningEventV1 } from "../../../packages/contracts/src/events/learning_event_v1.ts";
import type {
  ContentDraft,
  ContentPublicationHistoryItem,
  SaveDraftInput,
} from "../../../packages/contracts/src/cloud/wire.ts";
import { SupabaseAuthVerifier } from "./auth.ts";
import type {
  CommitPublicationInput,
  ContentStudioRepository,
  DraftSource,
  RollbackSource,
  StudioRole,
} from "./studio.ts";

export type CreateChallengeInput = {
  profileId: string;
  digest: Uint8Array;
  expiresAt: Date;
  actorUserId: string;
};

export interface CreatePairingRepository {
  createChallenge(input: CreateChallengeInput): Promise<string>;
}

export type PairingClaimOutcome =
  | {
    outcome: "paired";
    deviceBindingId: string;
    familyId: string;
    cloudProfileId: string;
    profileLocalId: string;
  }
  | {
    outcome:
      | "missing"
      | "expired"
      | "used"
      | "wrong"
      | "pairing_code_invalid"
      | "device_already_paired"
      | "rate_limited";
  };

export type ClaimChallengeInput = {
  digest: Uint8Array;
  deviceAuthUserId: string;
  deviceIdentifier: string;
  profileLocalId: string;
  displayName: string;
  networkDigest: Uint8Array;
};

export interface PairDeviceRepository {
  claimChallenge(input: ClaimChallengeInput): Promise<PairingClaimOutcome>;
}

export type IngestRepositoryResult = {
  acceptedEventIds: string[];
  alreadyPresentEventIds: string[];
  serverCursor: string;
};

export interface IngestionRepository {
  ingest(deviceAuthUserId: string, events: LearningEventV1[]): Promise<IngestRepositoryResult>;
}

type RpcErrorBody = {
  code?: unknown;
};

export class SupabaseRpcError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status: number) {
    super(code);
    this.name = "SupabaseRpcError";
    this.code = code;
    this.status = status;
  }
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

class ServiceRpcClient {
  constructor(
    private readonly supabaseUrl: string,
    private readonly serviceRoleKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async call<T>(name: string, body: Record<string, unknown>): Promise<T> {
    let response: Response;
    try {
      response = await this.fetcher(`${this.supabaseUrl}/rest/v1/rpc/${name}`, {
        method: "POST",
        headers: {
          apikey: this.serviceRoleKey,
          authorization: `Bearer ${this.serviceRoleKey}`,
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch {
      throw new SupabaseRpcError("rpc_unavailable", 503);
    }
    if (!response.ok) {
      let errorCode = "rpc_error";
      try {
        const payload = await response.json() as RpcErrorBody;
        if (typeof payload.code === "string") errorCode = payload.code;
      } catch {
        // The Edge response deliberately does not expose an upstream response body.
      }
      throw new SupabaseRpcError(errorCode, response.status);
    }
    try {
      return await response.json() as T;
    } catch {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
  }
}

class CallerRestClient {
  constructor(
    private readonly supabaseUrl: string,
    private readonly publishableKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async request<T>(
    path: string,
    accessToken: string,
    init: RequestInit,
  ): Promise<T> {
    let response: Response;
    try {
      const headers = new Headers(init.headers);
      headers.set("apikey", this.publishableKey);
      headers.set("authorization", `Bearer ${accessToken}`);
      headers.set("accept", "application/json");
      if (init.body !== undefined) headers.set("content-type", "application/json");
      response = await this.fetcher(`${this.supabaseUrl}/rest/v1/${path}`, { ...init, headers });
    } catch {
      throw new SupabaseRpcError("rpc_unavailable", 503);
    }
    if (!response.ok) {
      let errorCode = "rpc_error";
      try {
        const payload = await response.json() as RpcErrorBody;
        if (typeof payload.code === "string") errorCode = payload.code;
      } catch {
        // Upstream details never cross the Edge boundary.
      }
      throw new SupabaseRpcError(errorCode, response.status);
    }
    try {
      return await response.json() as T;
    } catch {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
  }

  call<T>(name: string, accessToken: string, body: Record<string, unknown>): Promise<T> {
    return this.request<T>(`rpc/${name}`, accessToken, {
      method: "POST",
      body: JSON.stringify(body),
    });
  }
}

type PairingClaimRow = {
  outcome?: unknown;
  device_id?: unknown;
  family_id?: unknown;
  profile_id?: unknown;
  profile_local_id?: unknown;
};

type IngestRpcResult = {
  accepted_event_ids?: unknown;
  already_present_event_ids?: unknown;
  server_cursor?: unknown;
};

type DraftSourceRow = {
  id?: unknown;
  activity_id?: unknown;
  revision?: unknown;
  package?: unknown;
};

type DraftWireRow = {
  id?: unknown;
  activityId?: unknown;
  title?: unknown;
  revision?: unknown;
  updatedAt?: unknown;
  package?: unknown;
};

type RollbackSourceRow = {
  publication_id?: unknown;
  activity_id?: unknown;
  content_version?: unknown;
  checksum?: unknown;
  package?: unknown;
  current_draft_id?: unknown;
  current_draft_revision?: unknown;
};

type PublicationHistoryRow = {
  publication_id?: unknown;
  activity_id?: unknown;
  content_version?: unknown;
  checksum?: unknown;
  status?: unknown;
  actor_id?: unknown;
  published_at?: unknown;
  effective_at?: unknown;
  source_revision?: unknown;
  reason?: unknown;
  validation_valid?: unknown;
  rollback_of_id?: unknown;
};

const DRAFT_SELECT = "id,activityId:activity_id,title,revision,updatedAt:updated_at,package";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function draftWire(row: DraftWireRow): ContentDraft {
  if (
    typeof row.id !== "string" || typeof row.activityId !== "string" ||
    typeof row.title !== "string" || typeof row.revision !== "number" ||
    typeof row.updatedAt !== "string" || !isRecord(row.package)
  ) {
    throw new SupabaseRpcError("rpc_invalid_response", 503);
  }
  return {
    id: row.id,
    activityId: row.activityId,
    title: row.title,
    revision: row.revision,
    updatedAt: row.updatedAt,
    package: row.package as ContentDraft["package"],
  };
}

export class SupabaseFunctionRepository
  implements
    CreatePairingRepository,
    PairDeviceRepository,
    IngestionRepository,
    ContentStudioRepository {
  constructor(
    private readonly rpc: ServiceRpcClient,
    private readonly caller: CallerRestClient,
  ) {}

  async createChallenge(input: CreateChallengeInput): Promise<string> {
    const result = await this.rpc.call<unknown>("create_pairing_challenge_for_service", {
      target_profile_id: input.profileId,
      challenge_digest: `\\x${hex(input.digest)}`,
      challenge_expires_at: input.expiresAt.toISOString(),
      actor_user_id: input.actorUserId,
    });
    if (typeof result !== "string") throw new SupabaseRpcError("rpc_invalid_response", 503);
    return result;
  }

  async claimChallenge(input: ClaimChallengeInput): Promise<PairingClaimOutcome> {
    const result = await this.rpc.call<PairingClaimRow[]>("claim_device_pairing_for_service", {
      challenge_digest: `\\x${hex(input.digest)}`,
      device_auth_user_id: input.deviceAuthUserId,
      device_identifier: input.deviceIdentifier,
      profile_local_identifier: input.profileLocalId,
      device_display_name: input.displayName,
      network_fingerprint: `\\x${hex(input.networkDigest)}`,
    });
    const row = result[0];
    if (row === undefined || typeof row.outcome !== "string") {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    if (row.outcome === "paired") {
      if (
        typeof row.device_id !== "string" || typeof row.family_id !== "string" ||
        typeof row.profile_id !== "string" || typeof row.profile_local_id !== "string"
      ) {
        throw new SupabaseRpcError("rpc_invalid_response", 503);
      }
      return {
        outcome: "paired",
        deviceBindingId: row.device_id,
        familyId: row.family_id,
        cloudProfileId: row.profile_id,
        profileLocalId: row.profile_local_id,
      };
    }
    if (
      row.outcome === "pairing_code_invalid" || row.outcome === "device_already_paired" ||
      row.outcome === "rate_limited"
    ) {
      return { outcome: row.outcome };
    }
    throw new SupabaseRpcError("rpc_invalid_response", 503);
  }

  async ingest(
    deviceAuthUserId: string,
    events: LearningEventV1[],
  ): Promise<IngestRepositoryResult> {
    const result = await this.rpc.call<IngestRpcResult>(
      "ingest_learning_event_batch_for_service",
      {
        device_auth_user_id: deviceAuthUserId,
        event_payloads: events,
      },
    );
    if (
      !Array.isArray(result.accepted_event_ids) ||
      !result.accepted_event_ids.every((id) => typeof id === "string") ||
      !Array.isArray(result.already_present_event_ids) ||
      !result.already_present_event_ids.every((id) => typeof id === "string") ||
      typeof result.server_cursor !== "string"
    ) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    return {
      acceptedEventIds: result.accepted_event_ids as string[],
      alreadyPresentEventIds: result.already_present_event_ids as string[],
      serverCursor: result.server_cursor,
    };
  }

  async hasRole(accessToken: string, role: StudioRole): Promise<boolean> {
    const result = await this.caller.call<unknown>("has_global_studio_role", accessToken, {
      required_role: role,
    });
    if (typeof result !== "boolean") throw new SupabaseRpcError("rpc_invalid_response", 503);
    return result;
  }

  async getDraft(draftIdOrActivityId: string): Promise<DraftSource | undefined> {
    const result = await this.rpc.call<DraftSourceRow[]>("get_content_draft_for_validation", {
      target_draft_id: draftIdOrActivityId,
    });
    if (!Array.isArray(result) || result.length > 1) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    const row = result[0];
    if (row === undefined) return undefined;
    if (
      typeof row.id !== "string" || typeof row.activity_id !== "string" ||
      typeof row.revision !== "number" || !isRecord(row.package)
    ) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    return {
      id: row.id,
      activityId: row.activity_id,
      revision: row.revision,
      package: row.package as unknown as DraftSource["package"],
    };
  }

  async saveDraft(accessToken: string, input: SaveDraftInput): Promise<ContentDraft> {
    const title = input.package.localizations["ko-KR"].title;
    const query = new URLSearchParams({ select: DRAFT_SELECT });
    let rows: DraftWireRow[];
    if (input.draftId === undefined) {
      rows = await this.caller.request<DraftWireRow[]>(
        `content_drafts?${query}`,
        accessToken,
        {
          method: "POST",
          headers: { prefer: "return=representation" },
          body: JSON.stringify({
            activity_id: input.package.activity_id,
            title,
            package: input.package,
          }),
        },
      );
    } else {
      query.set("id", `eq.${input.draftId}`);
      query.set("revision", `eq.${input.expectedRevision}`);
      rows = await this.caller.request<DraftWireRow[]>(
        `content_drafts?${query}`,
        accessToken,
        {
          method: "PATCH",
          headers: { prefer: "return=representation" },
          body: JSON.stringify({ title, package: input.package }),
        },
      );
      if (Array.isArray(rows) && rows.length === 0) {
        throw new SupabaseRpcError("draft_revision_conflict", 409);
      }
    }
    if (!Array.isArray(rows) || rows.length !== 1) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    return draftWire(rows[0]);
  }

  async commitPublication(input: CommitPublicationInput): Promise<string> {
    const result = await this.rpc.call<unknown>("commit_validated_content_publication", {
      target_draft_id: input.draftId,
      expected_revision: input.expectedRevision,
      published_package: input.publishedPackage,
      canonical_checksum: input.checksum,
      validation_report: input.validationReport,
      actor_user_id: input.actorUserId,
      target_effective_at: input.effectiveAt.toISOString(),
      publication_request_id: input.requestId,
      publication_reason: input.reason,
      rollback_publication_id: input.rollbackPublicationId,
    });
    if (typeof result !== "string") throw new SupabaseRpcError("rpc_invalid_response", 503);
    return result;
  }

  async getRollbackSource(publicationId: string): Promise<RollbackSource | undefined> {
    const result = await this.rpc.call<RollbackSourceRow[]>(
      "get_content_publication_for_rollback",
      { target_publication_id: publicationId },
    );
    if (!Array.isArray(result) || result.length > 1) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    const row = result[0];
    if (row === undefined) return undefined;
    if (
      typeof row.publication_id !== "string" || typeof row.activity_id !== "string" ||
      typeof row.content_version !== "string" || typeof row.checksum !== "string" ||
      !isRecord(row.package) || typeof row.current_draft_id !== "string" ||
      typeof row.current_draft_revision !== "number"
    ) {
      throw new SupabaseRpcError("rpc_invalid_response", 503);
    }
    return {
      publicationId: row.publication_id,
      activityId: row.activity_id,
      contentVersion: row.content_version,
      checksum: row.checksum,
      package: row.package as unknown as RollbackSource["package"],
      draftId: row.current_draft_id,
      draftRevision: row.current_draft_revision,
    };
  }

  async listPublicationHistory(
    accessToken: string,
    activityId?: string,
  ): Promise<ContentPublicationHistoryItem[]> {
    const rows = await this.caller.call<PublicationHistoryRow[]>(
      "get_content_publication_history",
      accessToken,
      { target_activity_id: activityId ?? null },
    );
    if (!Array.isArray(rows)) throw new SupabaseRpcError("rpc_invalid_response", 503);
    return rows.map((row) => {
      if (
        typeof row.publication_id !== "string" || typeof row.activity_id !== "string" ||
        typeof row.content_version !== "string" || typeof row.checksum !== "string" ||
        (row.status !== "pending" && row.status !== "active" && row.status !== "retired") ||
        (row.actor_id !== null && typeof row.actor_id !== "string") ||
        typeof row.published_at !== "string" || typeof row.effective_at !== "string" ||
        typeof row.source_revision !== "number" ||
        (row.reason !== null && typeof row.reason !== "string") ||
        typeof row.validation_valid !== "boolean" ||
        (row.rollback_of_id !== null && typeof row.rollback_of_id !== "string")
      ) {
        throw new SupabaseRpcError("rpc_invalid_response", 503);
      }
      return {
        id: row.publication_id,
        activityId: row.activity_id,
        contentVersion: row.content_version,
        checksum: row.checksum,
        status: row.status,
        publishedAt: row.published_at,
        effectiveAt: row.effective_at,
        publishedBy: row.actor_id,
        sourceRevision: row.source_revision,
        rollbackOfId: row.rollback_of_id,
        reason: row.reason,
        validationValid: row.validation_valid,
      };
    });
  }
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (value === undefined || value.length === 0) {
    throw new Error(`missing runtime setting: ${name}`);
  }
  return value;
}

function allowedOriginsFromEnvironment(): string[] {
  const configured = requiredEnvironment("MATHLAND_ALLOWED_ORIGINS");
  const origins = configured.split(",").map((item) => item.trim()).filter(Boolean);
  if (origins.length === 0 || origins.includes("*")) throw new Error("invalid CORS allowlist");
  for (const origin of origins) {
    const parsed = new URL(origin);
    if (
      parsed.origin !== origin || (parsed.protocol !== "https:" && parsed.hostname !== "localhost")
    ) {
      throw new Error("invalid CORS allowlist");
    }
  }
  return [...new Set(origins)];
}

export type SupabaseFunctionRuntime = {
  allowedOrigins: string[];
  auth: SupabaseAuthVerifier;
  pairingSecret: string;
  repository: SupabaseFunctionRepository;
};

export function createSupabaseFunctionRuntime(): SupabaseFunctionRuntime {
  const supabaseUrl = requiredEnvironment("SUPABASE_URL").replace(/\/$/, "");
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY")?.trim() ||
    requiredEnvironment("SUPABASE_ANON_KEY");
  const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  const pairingSecret = requiredEnvironment("PAIRING_CODE_HMAC_SECRET");
  if (pairingSecret.length < 32) throw new Error("pairing HMAC secret is too short");
  const rpc = new ServiceRpcClient(supabaseUrl, serviceRoleKey);
  const caller = new CallerRestClient(supabaseUrl, publishableKey);
  return {
    allowedOrigins: allowedOriginsFromEnvironment(),
    auth: new SupabaseAuthVerifier(supabaseUrl, publishableKey),
    pairingSecret,
    repository: new SupabaseFunctionRepository(rpc, caller),
  };
}
