import type { AuthVerifier } from "../_shared/auth.ts";
import {
  CreatePairingCodeRequestSchema,
  generatePairingCode,
  hmacPairingCode,
} from "../_shared/contracts.ts";
import {
  errorResponse,
  HttpDiagnosticError,
  knownDiagnostic,
  prepareRequest,
  readJson,
  successResponse,
  unexpectedError,
} from "../_shared/http.ts";
import {
  type CreatePairingRepository,
  createSupabaseFunctionRuntime,
} from "../_shared/supabase.ts";

export type CreatePairingCodeDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  clock: { now(): Date };
  codeGenerator: () => string;
  pairingSecret: string;
  repository: CreatePairingRepository;
  requestId: () => string;
};

function errorCode(error: unknown): string | undefined {
  return typeof error === "object" && error !== null && "code" in error
    ? String(error.code)
    : undefined;
}

export async function createPairingCode(
  request: Request,
  dependencies: CreatePairingCodeDependencies,
): Promise<Response> {
  const context = prepareRequest(request, dependencies.allowedOrigins, dependencies.requestId);
  if (context.earlyResponse !== undefined) return context.earlyResponse;

  try {
    const identity = await dependencies.auth.verifyBearer(request);
    if (identity.isAnonymous) {
      throw new HttpDiagnosticError(403, {
        code: "guardian_required",
        message: "보호자 계정이 필요합니다.",
        retryable: false,
      });
    }

    const parsed = CreatePairingCodeRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_pairing_request",
        message: "프로필 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }
    const code = dependencies.codeGenerator();
    if (!/^\d{6}$/.test(code)) {
      return unexpectedError(
        context.requestId,
        "pairing_service_unavailable",
        "페어링 서비스를 사용할 수 없습니다.",
        context.headers,
      );
    }
    const digest = await hmacPairingCode(dependencies.pairingSecret, code);
    const expiresAt = new Date(dependencies.clock.now().getTime() + 10 * 60 * 1000);
    await dependencies.repository.createChallenge({
      profileId: parsed.data.profile_id,
      digest,
      expiresAt,
      actorUserId: identity.id,
    });

    return successResponse(
      context.requestId,
      201,
      { code, expires_at: expiresAt.toISOString() },
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
    if (errorCode(error) === "42501") {
      return errorResponse(
        context.requestId,
        403,
        {
          code: "profile_access_denied",
          message: "이 프로필의 페어링 코드를 만들 권한이 없습니다.",
          retryable: false,
        },
        context.headers,
      );
    }
    return unexpectedError(
      context.requestId,
      "pairing_service_unavailable",
      "페어링 서비스를 사용할 수 없습니다.",
      context.headers,
    );
  }
}

function runtimeDependencies(): CreatePairingCodeDependencies {
  const runtime = createSupabaseFunctionRuntime();
  return {
    allowedOrigins: runtime.allowedOrigins,
    auth: runtime.auth,
    clock: { now: () => new Date() },
    codeGenerator: generatePairingCode,
    pairingSecret: runtime.pairingSecret,
    repository: runtime.repository,
    requestId: () => crypto.randomUUID(),
  };
}

if (import.meta.main) {
  const dependencies = runtimeDependencies();
  Deno.serve((request) => createPairingCode(request, dependencies));
}
