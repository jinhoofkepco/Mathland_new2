import type { AuthVerifier } from "../_shared/auth.ts";
import { ValidateDraftRequestSchema } from "../_shared/contracts.ts";
import { HttpDiagnosticError, prepareRequest, readJson, wireResponse } from "../_shared/http.ts";
import {
  type ContentStudioRepository,
  requireStudioRole,
  studioErrorResponse,
} from "../_shared/studio.ts";
import { createSupabaseFunctionRuntime } from "../_shared/supabase.ts";
import { ValidationReportWireSchema } from "../../../packages/contracts/src/cloud/wire.ts";
import { validateActivityDraft } from "../../../packages/contracts/src/content/validate.ts";

export type ValidateDraftDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  repository: ContentStudioRepository;
  requestId: () => string;
};

export async function validateDraft(
  request: Request,
  dependencies: ValidateDraftDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;
  try {
    const parsed = ValidateDraftRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_validation_request",
        message: "초안 검증 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const identity = await dependencies.auth.verifyBearer(request);
    await requireStudioRole(dependencies.repository, identity, "editor");
    const stored = await dependencies.repository.getDraft(parsed.data.draftId);
    if (stored === undefined) {
      throw new HttpDiagnosticError(404, {
        code: "draft_not_found",
        message: "초안을 찾을 수 없습니다.",
        retryable: false,
      });
    }
    const candidate = parsed.data.package === undefined ? stored.package : parsed.data.package;
    const report = validateActivityDraft(candidate);
    const candidateActivity = typeof candidate === "object" && candidate !== null &&
        "activity_id" in candidate && typeof candidate.activity_id === "string"
      ? candidate.activity_id
      : undefined;
    if (candidateActivity !== undefined && candidateActivity !== stored.activityId) {
      report.issues.push({
        code: "DRAFT_ACTIVITY_MISMATCH",
        path: ["activity_id"],
        message: "검증 패키지의 활동 ID가 저장된 초안과 다릅니다.",
      });
      report.valid = false;
    }
    const wire = ValidationReportWireSchema.safeParse(report);
    if (!wire.success) {
      throw new HttpDiagnosticError(503, {
        code: "validation_service_invalid_response",
        message: "초안 검증 응답을 확인할 수 없습니다.",
        retryable: true,
      });
    }
    return wireResponse(200, wire.data, context.headers);
  } catch (error) {
    return studioErrorResponse(
      error,
      context.requestId,
      context.headers,
      "validation_service_unavailable",
      "초안을 검증할 수 없습니다.",
    );
  }
}

function runtimeDependencies(): ValidateDraftDependencies {
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
  Deno.serve((request) => validateDraft(request, dependencies));
}
