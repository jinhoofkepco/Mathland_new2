import type { AuthVerifier } from "../_shared/auth.ts";
import { hmacPairingCode, PairDeviceRequestSchema } from "../_shared/contracts.ts";
import {
  errorResponse,
  HttpDiagnosticError,
  knownDiagnostic,
  prepareRequest,
  readJson,
  unexpectedError,
  wireResponse,
} from "../_shared/http.ts";
import { pairingNetworkDigest } from "../_shared/network.ts";
import { createSupabaseFunctionRuntime, type PairDeviceRepository } from "../_shared/supabase.ts";

export type PairDeviceDependencies = {
  allowedOrigins: readonly string[];
  auth: AuthVerifier;
  pairingSecret: string;
  repository: PairDeviceRepository;
  requestId: () => string;
};

export async function pairDevice(
  request: Request,
  dependencies: PairDeviceDependencies,
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
    const parsed = PairDeviceRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      throw new HttpDiagnosticError(400, {
        code: "invalid_pairing_request",
        message: "페어링 정보가 올바르지 않습니다.",
        retryable: false,
      });
    }

    const digest = await hmacPairingCode(dependencies.pairingSecret, parsed.data.code);
    const networkDigest = await pairingNetworkDigest(dependencies.pairingSecret, request);
    const result = await dependencies.repository.claimChallenge({
      digest,
      deviceAuthUserId: identity.id,
      deviceIdentifier: parsed.data.deviceId,
      profileLocalId: parsed.data.profileLocalId,
      displayName: parsed.data.displayName ?? "MathLand Android",
      networkDigest,
    });
    if (result.outcome === "paired") {
      return wireResponse(
        200,
        {
          deviceBindingId: result.deviceBindingId,
          familyId: result.familyId,
          cloudProfileId: result.cloudProfileId,
          profileLocalId: result.profileLocalId,
        },
        context.headers,
      );
    }
    if (result.outcome === "rate_limited") {
      return errorResponse(
        context.requestId,
        429,
        {
          code: "pairing_rate_limited",
          message: "잠시 후 다시 시도해 주세요.",
          retryable: true,
        },
        context.headers,
      );
    }
    return errorResponse(
      context.requestId,
      400,
      {
        code: "pairing_code_invalid",
        message: "페어링 코드가 유효하지 않습니다.",
        retryable: false,
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
    return unexpectedError(
      context.requestId,
      "pairing_service_unavailable",
      "페어링 서비스를 사용할 수 없습니다.",
      context.headers,
    );
  }
}

function runtimeDependencies(): PairDeviceDependencies {
  const runtime = createSupabaseFunctionRuntime();
  return {
    allowedOrigins: runtime.allowedOrigins,
    auth: runtime.auth,
    pairingSecret: runtime.pairingSecret,
    repository: runtime.repository,
    requestId: () => crypto.randomUUID(),
  };
}

if (import.meta.main) {
  const dependencies = runtimeDependencies();
  Deno.serve((request) => pairDevice(request, dependencies));
}
