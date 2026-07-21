import type {
  ContentDraft,
  ContentPublication,
  ContentPublicationHistoryItem,
  SaveDraftInput,
  ValidationReportWire,
} from "../../../packages/contracts/src/cloud/wire.ts";
import type { AuthIdentity } from "./auth.ts";
import { errorResponse, HttpDiagnosticError, knownDiagnostic, unexpectedError } from "./http.ts";

export type StudioRole = "editor" | "owner";

export type DraftSource = {
  id: string;
  activityId: string;
  revision: number;
  package: ContentDraft["package"];
};

export type RollbackSource = {
  publicationId: string;
  activityId: string;
  contentVersion: string;
  checksum: string;
  package: ContentPublication["package"];
  /** Current draft identity is supplied atomically by the production rollback RPC. */
  draftId?: string;
  draftRevision?: number;
};

export type CommitPublicationInput = {
  draftId: string;
  expectedRevision: number;
  publishedPackage: ContentPublication["package"];
  checksum: string;
  validationReport: ValidationReportWire;
  actorUserId: string;
  effectiveAt: Date;
  requestId: string;
  reason: string;
  rollbackPublicationId: string | null;
};

export interface ContentStudioRepository {
  hasRole(accessToken: string, role: StudioRole): Promise<boolean>;
  getDraft(draftIdOrActivityId: string): Promise<DraftSource | undefined>;
  saveDraft(accessToken: string, input: SaveDraftInput): Promise<ContentDraft>;
  commitPublication(input: CommitPublicationInput): Promise<string>;
  getRollbackSource(publicationId: string): Promise<RollbackSource | undefined>;
  listPublicationHistory(
    accessToken: string,
    activityId?: string,
  ): Promise<ContentPublicationHistoryItem[]>;
}

export function studioAccessToken(identity: AuthIdentity): string {
  if (identity.isAnonymous || identity.accessToken === undefined) {
    throw new HttpDiagnosticError(403, {
      code: "studio_role_required",
      message: "콘텐츠 Studio 권한이 필요합니다.",
      retryable: false,
    });
  }
  return identity.accessToken;
}

export async function requireStudioRole(
  repository: ContentStudioRepository,
  identity: AuthIdentity,
  role: StudioRole,
): Promise<string> {
  const accessToken = studioAccessToken(identity);
  const hasRequestedRole = await repository.hasRole(accessToken, role);
  const allowed = hasRequestedRole ||
    (role === "editor" && await repository.hasRole(accessToken, "owner"));
  if (!allowed) {
    throw new HttpDiagnosticError(403, {
      code: "studio_role_required",
      message: role === "owner"
        ? "콘텐츠 소유자 권한이 필요합니다."
        : "콘텐츠 편집 권한이 필요합니다.",
      retryable: false,
    });
  }
  return accessToken;
}

export function studioErrorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : undefined;
}

export function studioErrorResponse(
  error: unknown,
  requestId: string,
  headers: Headers,
  unavailableCode: string,
  unavailableMessage: string,
): Response {
  const diagnostic = knownDiagnostic(error);
  if (diagnostic !== undefined) {
    return errorResponse(requestId, diagnostic.status, diagnostic.diagnostic, headers);
  }
  const code = studioErrorCode(error);
  if (code === "draft_revision_conflict" || code === "40001") {
    return errorResponse(
      requestId,
      409,
      {
        code: "draft_revision_conflict",
        message: "초안이 다른 곳에서 변경되었습니다. 새로고침 후 다시 시도해 주세요.",
        retryable: false,
      },
      headers,
    );
  }
  if (code === "42501") {
    return errorResponse(
      requestId,
      403,
      {
        code: "studio_role_required",
        message: "콘텐츠 Studio 권한이 필요합니다.",
        retryable: false,
      },
      headers,
    );
  }
  if (code === "23505") {
    return errorResponse(
      requestId,
      409,
      {
        code: "draft_activity_conflict",
        message: "이 활동의 초안이 이미 존재합니다.",
        retryable: false,
      },
      headers,
    );
  }
  return unexpectedError(requestId, unavailableCode, unavailableMessage, headers);
}
