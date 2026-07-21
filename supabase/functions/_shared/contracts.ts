import { z } from "zod";
import {
  CloudUuidSchema,
  CreatePairingCodeRequestSchema,
  DevicePairingRequestSchema,
  PublicationReasonSchema,
  SaveDraftInputSchema,
} from "../../../packages/contracts/src/cloud/wire.ts";
import {
  type LearningEventV1,
  LearningEventV1Schema,
} from "../../../packages/contracts/src/events/learning_event_v1.ts";
import { HttpDiagnosticError } from "./http.ts";

export {
  CreatePairingCodeRequestSchema,
  DevicePairingRequestSchema as PairDeviceRequestSchema,
  SaveDraftInputSchema,
};

export const ValidateDraftRequestSchema = z.strictObject({
  draftId: CloudUuidSchema,
  // Deliberately unknown: validation must report malformed package fields instead of
  // rejecting them at the transport boundary.
  package: z.unknown().optional(),
});

export const PublishDraftRequestSchema = z.strictObject({
  draftId: CloudUuidSchema,
  expectedRevision: z.number().int().positive(),
  effectiveAt: z.iso.datetime({ offset: true }).optional(),
  reason: PublicationReasonSchema.optional(),
});

export const ContentHistoryRequestSchema = z.strictObject({
  activityId: z.string().min(1).max(128).optional(),
});

export const RollbackPublicationRequestSchema = z.strictObject({
  publicationId: CloudUuidSchema,
  reason: PublicationReasonSchema,
});

export type IngestResponse = {
  accepted_event_ids: string[];
  already_present_event_ids: string[];
  server_cursor: string;
};

export async function hmacPairingCode(secret: string, code: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(code)),
  );
}

export function generatePairingCode(): string {
  const range = 1_000_000;
  const uint32Range = 0x1_0000_0000;
  const unbiasedLimit = uint32Range - (uint32Range % range);
  const sample = new Uint32Array(1);
  do {
    crypto.getRandomValues(sample);
  } while (sample[0] >= unbiasedLimit);
  return sample[0].toString().padStart(6, "0");
}

function invalidBatch(code: string, message: string): never {
  throw new HttpDiagnosticError(400, { code, message, retryable: false });
}

export function parseLearningEventBatch(value: unknown): LearningEventV1[] {
  if (
    typeof value !== "object" || value === null || Array.isArray(value) ||
    Object.keys(value).length !== 1 || !("events" in value) || !Array.isArray(value.events) ||
    value.events.length < 1 || value.events.length > 100
  ) {
    invalidBatch("invalid_event_batch", "이벤트는 1개부터 100개까지 전송할 수 있습니다.");
  }

  const events: LearningEventV1[] = [];
  for (const candidate of value.events) {
    const result = LearningEventV1Schema.safeParse(candidate);
    if (!result.success) {
      invalidBatch("invalid_event_schema", "학습 이벤트 형식이 올바르지 않습니다.");
    }
    events.push(result.data);
  }

  const first = events[0];
  let previousSequence = 0;
  const eventIds = new Set<string>();
  for (const event of events) {
    if (event.sequence <= previousSequence) {
      invalidBatch("event_sequence_invalid", "이벤트 순서가 올바르지 않습니다.");
    }
    previousSequence = event.sequence;
    if (event.device_id !== first.device_id || event.profile_id !== first.profile_id) {
      invalidBatch(
        "event_binding_inconsistent",
        "한 번에 하나의 기기와 프로필만 전송할 수 있습니다.",
      );
    }
    if (eventIds.has(event.event_id)) {
      invalidBatch("duplicate_event_id", "같은 이벤트 ID를 한 번에 두 번 전송할 수 없습니다.");
    }
    eventIds.add(event.event_id);
  }
  return events;
}
