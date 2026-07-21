import { z } from "zod";
import type { AuthVerifier } from "../_shared/auth.ts";
import { ContentHistoryRequestSchema } from "../_shared/contracts.ts";
import { HttpDiagnosticError, prepareRequest, readJson, wireResponse } from "../_shared/http.ts";
import {
  type ContentStudioRepository,
  requireStudioRole,
  studioErrorResponse,
} from "../_shared/studio.ts";
import { createSupabaseFunctionRuntime } from "../_shared/supabase.ts";
import { ContentPublicationHistoryItemSchema } from "../../../packages/contracts/src/cloud/wire.ts";

export type ContentHistoryDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  repository: ContentStudioRepository;
  requestId: () => string;
};

export async function contentHistory(
  request: Request,
  dependencies: ContentHistoryDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;
  try {
    const parsed = ContentHistoryRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_history_request",
        message: "배포 이력 조회 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const identity = await dependencies.auth.verifyBearer(request);
    const token = await requireStudioRole(dependencies.repository, identity, "owner");
    const history = await dependencies.repository.listPublicationHistory(
      token,
      parsed.data.activityId,
    );
    const wire = z.array(ContentPublicationHistoryItemSchema).safeParse(history);
    if (!wire.success) {
      throw new HttpDiagnosticError(503, {
        code: "history_service_invalid_response",
        message: "배포 이력 응답을 확인할 수 없습니다.",
        retryable: true,
      });
    }
    return wireResponse(200, wire.data, context.headers);
  } catch (error) {
    return studioErrorResponse(
      error,
      context.requestId,
      context.headers,
      "history_service_unavailable",
      "배포 이력을 불러올 수 없습니다.",
    );
  }
}

function runtimeDependencies(): ContentHistoryDependencies {
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
  Deno.serve((request) => contentHistory(request, dependencies));
}
