import type { AuthVerifier } from "../_shared/auth.ts";
import { parseLearningEventBatch } from "../_shared/contracts.ts";
import {
  errorResponse,
  HttpDiagnosticError,
  knownDiagnostic,
  prepareRequest,
  readJson,
  successResponse,
  unexpectedError,
} from "../_shared/http.ts";
import { createSupabaseFunctionRuntime, type IngestionRepository } from "../_shared/supabase.ts";

export type IngestEventsDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  repository: IngestionRepository;
  requestId: () => string;
};

function errorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : undefined;
}

export async function ingestEvents(
  request: Request,
  dependencies: IngestEventsDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;

  try {
    const identity = await dependencies.auth.verifyBearer(request);
    if (!identity.isAnonymous) {
      throw new HttpDiagnosticError(403, {
        code: "anonymous_device_required",
        message: "익명 기기 인증이 필요합니다.",
        retryable: false,
      });
    }
    const events = parseLearningEventBatch(await readJson(request));
    const result = await dependencies.repository.ingest(identity.id, events);
    return successResponse(
      context.requestId,
      200,
      {
        accepted_event_ids: result.acceptedEventIds,
        already_present_event_ids: result.alreadyPresentEventIds,
        server_cursor: result.serverCursor,
      },
      context.headers,
    );
  } catch (error) {
    const diagnostic = knownDiagnostic(error);
    if (diagnostic !== undefined) {
      return errorResponse(
        context.requestId,
        diagnostic.status,
        diagnostic.diagnostic,
        context.headers,
      );
    }
    const code = errorCode(error);
    if (code === "42501") {
      return errorResponse(
        context.requestId,
        403,
        {
          code: "device_binding_denied",
          message: "이 기기의 학습 이벤트를 전송할 권한이 없습니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    if (code === "23505") {
      return errorResponse(
        context.requestId,
        409,
        {
          code: "event_id_conflict",
          message: "같은 ID의 다른 이벤트가 이미 존재합니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    if (code === "22023") {
      return errorResponse(
        context.requestId,
        400,
        {
          code: "invalid_event_batch",
          message: "이벤트 묶음이 올바르지 않습니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    return unexpectedError(
      context.requestId,
      "ingest_service_unavailable",
      "동기화 서비스를 사용할 수 없습니다.",
      context.headers,
    );
  }
}

function runtimeDependencies(): IngestEventsDependencies {
  const runtime = createSupabaseFunctionRuntime();
  return {
    allowedOrigins: runtime.allowedOrigins,
    auth: runtime.auth,
    repository: runtime.repository,
    requestId: () => crypto.randomUUID(),
  };
}

if (import.meta.main) {
  const dependencies = runtimeDependencies();
  Deno.serve((request) => ingestEvents(request, dependencies));
}
