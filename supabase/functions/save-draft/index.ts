import type { AuthVerifier } from "../_shared/auth.ts";
import { SaveDraftInputSchema } from "../_shared/contracts.ts";
import { HttpDiagnosticError, prepareRequest, readJson, wireResponse } from "../_shared/http.ts";
import {
  type ContentStudioRepository,
  requireStudioRole,
  studioErrorResponse,
} from "../_shared/studio.ts";
import { createSupabaseFunctionRuntime } from "../_shared/supabase.ts";
import { ContentDraftSchema } from "../../../packages/contracts/src/cloud/wire.ts";

export type SaveDraftDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  repository: ContentStudioRepository;
  requestId: () => string;
};

export async function saveDraft(
  request: Request,
  dependencies: SaveDraftDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;
  try {
    const parsed = SaveDraftInputSchema.safeParse(await readJson(request));
    if (
      !parsed.success ||
      (parsed.data.draftId === undefined) !== (parsed.data.expectedRevision === undefined)
    ) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_draft_request",
        message: "초안 저장 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const identity = await dependencies.auth.verifyBearer(request);
    const token = await requireStudioRole(dependencies.repository, identity, "editor");
    const saved = await dependencies.repository.saveDraft(token, parsed.data);
    const wire = ContentDraftSchema.safeParse(saved);
    if (!wire.success) {
      throw new HttpDiagnosticError(503, {
        code: "draft_service_invalid_response",
        message: "초안 저장 응답을 확인할 수 없습니다.",
        retryable: true,
      });
    }
    return wireResponse(200, wire.data, context.headers);
  } catch (error) {
    return studioErrorResponse(
      error,
      context.requestId,
      context.headers,
      "draft_service_unavailable",
      "초안을 저장할 수 없습니다.",
    );
  }
}

function runtimeDependencies(): SaveDraftDependencies {
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
  Deno.serve((request) => saveDraft(request, dependencies));
}
