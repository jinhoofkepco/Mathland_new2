import type { LearningEventV1 } from "../../../packages/contracts/src/events/learning_event_v1.ts";
import { SupabaseAuthVerifier } from "./auth.ts";

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
    deviceId: string;
    familyId: string;
    profileId: string;
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
  displayName: string;
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

export class SupabaseFunctionRepository
  implements CreatePairingRepository, PairDeviceRepository, IngestionRepository {
  constructor(private readonly rpc: ServiceRpcClient) {}

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
      device_display_name: input.displayName,
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
        deviceId: row.device_id,
        familyId: row.family_id,
        profileId: row.profile_id,
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
  return {
    allowedOrigins: allowedOriginsFromEnvironment(),
    auth: new SupabaseAuthVerifier(supabaseUrl, publishableKey),
    pairingSecret,
    repository: new SupabaseFunctionRepository(rpc),
  };
}
