import type { AuthVerifier } from "../_shared/auth.ts";
import { RollbackPublicationRequestSchema } from "../_shared/contracts.ts";
import {
  errorResponse,
  HttpDiagnosticError,
  prepareRequest,
  readJson,
  wireResponse,
} from "../_shared/http.ts";
import {
  type ContentStudioRepository,
  requireStudioRole,
  studioErrorCode,
  studioErrorResponse,
} from "../_shared/studio.ts";
import { createSupabaseFunctionRuntime } from "../_shared/supabase.ts";
import {
  ContentPublicationSchema,
  ValidationReportWireSchema,
} from "../../../packages/contracts/src/cloud/wire.ts";
import { validatePublishedActivity } from "../../../packages/contracts/src/content/validate.ts";

export type RollbackPublicationDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  clock: { now(): Date };
  operationId: () => string;
  repository: ContentStudioRepository;
  requestId: () => string;
};

export async function rollbackPublication(
  request: Request,
  dependencies: RollbackPublicationDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;
  try {
    const parsed = RollbackPublicationRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_rollback_request",
        message: "롤백 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const identity = await dependencies.auth.verifyBearer(request);
    await requireStudioRole(dependencies.repository, identity, "owner");
    const source = await dependencies.repository.getRollbackSource(parsed.data.publicationId);
    if (source === undefined) {
      throw new HttpDiagnosticError(404, {
        code: "publication_not_found",
        message: "롤백할 수 있는 배포 이력을 찾을 수 없습니다.",
        retryable: false,
      });
    }
    const rawReport = validatePublishedActivity(source.package);
    const report = ValidationReportWireSchema.parse(rawReport);
    if (!report.valid || source.package.checksum !== source.checksum) {
      throw new HttpDiagnosticError(422, {
        code: "historical_validation_failed",
        message: "검증되지 않은 과거 콘텐츠는 복원할 수 없습니다.",
        retryable: false,
      });
    }

    let draftId = source.draftId;
    let draftRevision = source.draftRevision;
    if (draftId === undefined || draftRevision === undefined) {
      // Test doubles and old projections can still resolve the current draft here;
      // production returns both fields in the locked rollback projection.
      const currentDraft = await dependencies.repository.getDraft(source.activityId);
      if (currentDraft === undefined || currentDraft.activityId !== source.activityId) {
        throw new HttpDiagnosticError(409, {
          code: "rollback_draft_conflict",
          message: "현재 활동 초안과 과거 배포를 연결할 수 없습니다.",
          retryable: false,
        });
      }
      draftId = currentDraft.id;
      draftRevision = currentDraft.revision;
    }

    const now = dependencies.clock.now();
    await dependencies.repository.commitPublication({
      draftId,
      expectedRevision: draftRevision,
      publishedPackage: source.package,
      checksum: source.checksum,
      validationReport: report,
      actorUserId: identity.id,
      effectiveAt: new Date(now),
      requestId: dependencies.operationId(),
      reason: parsed.data.reason,
      rollbackPublicationId: source.publicationId,
    });
    const response = ContentPublicationSchema.parse({
      activityId: source.activityId,
      contentVersion: source.contentVersion,
      publishedAt: now.toISOString(),
      package: source.package,
    });
    return wireResponse(200, response, context.headers);
  } catch (error) {
    if (studioErrorCode(error) === "22023") {
      return errorResponse(
        context.requestId,
        409,
        {
          code: "rollback_conflict",
          message: "현재 콘텐츠 상태에서는 이 배포로 복원할 수 없습니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    return studioErrorResponse(
      error,
      context.requestId,
      context.headers,
      "rollback_service_unavailable",
      "콘텐츠를 복원할 수 없습니다.",
    );
  }
}

function runtimeDependencies(): RollbackPublicationDependencies {
  const runtime = createSupabaseFunctionRuntime();
  return {
    allowedOrigins: runtime.allowedOrigins,
    auth: runtime.auth,
    clock: { now: () => new Date() },
    operationId: () => crypto.randomUUID(),
    repository: runtime.repository,
    requestId: () => crypto.randomUUID(),
  };
}

if (import.meta.main) {
  const dependencies = runtimeDependencies();
  Deno.serve((request) => rollbackPublication(request, dependencies));
}
