import {
  errorResponse,
  HttpDiagnosticError,
  knownDiagnostic,
  readJson,
  resolveRequestId,
  unexpectedError,
  wireResponse,
} from "../_shared/http.ts";
import {
  ActivationWorkerRequestSchema,
  hasValidSchedulerBearer,
  type PublicationActivationRepository,
} from "../_shared/scheduler.ts";
import { createSupabaseSchedulerRuntime } from "../_shared/supabase.ts";

const DEFAULT_BATCH_LIMIT = 25;

export type ActivatePublicationsDependencies = {
  schedulerSecret: string;
  repository: PublicationActivationRepository;
  operationId: () => string;
  requestId: () => string;
};

export async function activatePublications(
  request: Request,
  dependencies: ActivatePublicationsDependencies,
): Promise<Response> {
  const requestId = resolveRequestId(request, dependencies.requestId);
  const headers = new Headers({
    "cache-control": "no-store",
    "x-request-id": requestId,
  });

  if (request.method !== "POST") {
    return errorResponse(
      requestId,
      405,
      {
        code: "method_not_allowed",
        message: "POST 요청만 사용할 수 있습니다.",
        retryable: false,
      },
      headers,
    );
  }

  try {
    if (!await hasValidSchedulerBearer(request, dependencies.schedulerSecret)) {
      throw new HttpDiagnosticError(401, {
        code: "scheduler_auth_invalid",
        message: "예약 작업 인증 정보가 유효하지 않습니다.",
        retryable: false,
      });
    }

    const parsed = ActivationWorkerRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_activation_request",
        message: "예약 활성화 요청이 올바르지 않습니다.",
        retryable: false,
      });
    }

    const publicationIds = await dependencies.repository.listDuePublicationIds(
      parsed.data.batchLimit ?? DEFAULT_BATCH_LIMIT,
    );
    for (const publicationId of publicationIds) {
      await dependencies.repository.activatePublication(
        publicationId,
        dependencies.operationId(),
      );
    }

    return wireResponse(
      200,
      { processed: publicationIds.length, publicationIds },
      headers,
    );
  } catch (error) {
    const diagnostic = knownDiagnostic(error);
    if (diagnostic !== undefined) {
      return errorResponse(
        requestId,
        diagnostic.status,
        diagnostic.diagnostic,
        headers,
      );
    }
    return unexpectedError(
      requestId,
      "activation_service_unavailable",
      "예약 활성화 서비스를 사용할 수 없습니다.",
      headers,
    );
  }
}

function runtimeDependencies(): ActivatePublicationsDependencies {
  const runtime = createSupabaseSchedulerRuntime();
  return {
    schedulerSecret: runtime.schedulerSecret,
    repository: runtime.repository,
    operationId: () => crypto.randomUUID(),
    requestId: () => crypto.randomUUID(),
  };
}

if (import.meta.main) {
  const dependencies = runtimeDependencies();
  Deno.serve((request) => activatePublications(request, dependencies));
}
