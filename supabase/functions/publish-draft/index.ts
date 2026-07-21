import type { AuthVerifier } from "../_shared/auth.ts";
import { PublishDraftRequestSchema } from "../_shared/contracts.ts";
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
  type ContentPublication,
  ContentPublicationSchema,
  ValidationReportWireSchema,
} from "../../../packages/contracts/src/cloud/wire.ts";
import { contentChecksum } from "../../../packages/contracts/src/content/checksum.ts";
import { validateActivityDraft } from "../../../packages/contracts/src/content/validate.ts";

export type PublishDraftDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  clock: { now(): Date };
  operationId: () => string;
  repository: ContentStudioRepository;
  requestId: () => string;
};

export async function publishDraft(
  request: Request,
  dependencies: PublishDraftDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;
  try {
    const parsed = PublishDraftRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_publication_request",
        message: "배포 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const identity = await dependencies.auth.verifyBearer(request);
    await requireStudioRole(dependencies.repository, identity, "owner");
    const stored = await dependencies.repository.getDraft(parsed.data.draftId);
    if (stored === undefined) {
      throw new HttpDiagnosticError(404, {
        code: "draft_not_found",
        message: "초안을 찾을 수 없습니다.",
        retryable: false,
      });
    }
    if (stored.revision !== parsed.data.expectedRevision) {
      throw new HttpDiagnosticError(409, {
        code: "draft_revision_conflict",
        message: "초안이 다른 곳에서 변경되었습니다. 새로고침 후 다시 시도해 주세요.",
        retryable: false,
      });
    }
    const rawReport = validateActivityDraft(stored.package);
    const report = ValidationReportWireSchema.parse(rawReport);
    if (!report.valid) {
      throw new HttpDiagnosticError(422, {
        code: "draft_validation_failed",
        message: "검증 오류가 있는 초안은 배포할 수 없습니다.",
        retryable: false,
      });
    }
    const checksum = contentChecksum(stored.package);
    const publishedPackage = {
      ...structuredClone(stored.package),
      checksum,
    } as ContentPublication["package"];
    const publishedValidation = ContentPublicationSchema.shape.package.safeParse(publishedPackage);
    if (!publishedValidation.success) {
      throw new HttpDiagnosticError(422, {
        code: "draft_validation_failed",
        message: "검증 오류가 있는 초안은 배포할 수 없습니다.",
        retryable: false,
      });
    }
    const now = dependencies.clock.now();
    const effectiveAt = parsed.data.effectiveAt === undefined
      ? new Date(now)
      : new Date(parsed.data.effectiveAt);
    await dependencies.repository.commitPublication({
      draftId: stored.id,
      expectedRevision: parsed.data.expectedRevision,
      publishedPackage: publishedValidation.data,
      checksum,
      validationReport: report,
      actorUserId: identity.id,
      effectiveAt,
      requestId: dependencies.operationId(),
      reason: parsed.data.reason ?? "Studio publication",
      rollbackPublicationId: null,
    });
    const response = ContentPublicationSchema.parse({
      activityId: stored.activityId,
      contentVersion: publishedValidation.data.content_version,
      publishedAt: now.toISOString(),
      package: publishedValidation.data,
    });
    return wireResponse(200, response, context.headers);
  } catch (error) {
    if (studioErrorCode(error) === "22023") {
      return errorResponse(
        context.requestId,
        409,
        {
          code: "publication_conflict",
          message: "현재 콘텐츠 상태에서는 배포할 수 없습니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    return studioErrorResponse(
      error,
      context.requestId,
      context.headers,
      "publication_service_unavailable",
      "콘텐츠를 배포할 수 없습니다.",
    );
  }
}

function runtimeDependencies(): PublishDraftDependencies {
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
  Deno.serve((request) => publishDraft(request, dependencies));
}
