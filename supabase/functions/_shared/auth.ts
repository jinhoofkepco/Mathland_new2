import { HttpDiagnosticError } from "./http.ts";

export type AuthIdentity = {
  id: string;
  isAnonymous: boolean;
  accessToken?: string;
};

export interface AuthVerifier {
  verifyBearer(request: Request): Promise<AuthIdentity>;
}

type AuthUserPayload = {
  id?: unknown;
  is_anonymous?: unknown;
  app_metadata?: { provider?: unknown };
};

function bearerToken(request: Request): string {
  const authorization = request.headers.get("authorization");
  const match = /^Bearer ([^\s]+)$/.exec(authorization ?? "");
  if (match === null) {
    throw new HttpDiagnosticError(401, {
      code: "auth_required",
      message: "인증이 필요합니다.",
      retryable: false,
    });
  }
  return match[1];
}

export class SupabaseAuthVerifier implements AuthVerifier {
  constructor(
    private readonly supabaseUrl: string,
    private readonly publishableKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async verifyBearer(request: Request): Promise<AuthIdentity> {
    const token = bearerToken(request);
    let response: Response;
    try {
      response = await this.fetcher(`${this.supabaseUrl}/auth/v1/user`, {
        method: "GET",
        headers: {
          apikey: this.publishableKey,
          authorization: `Bearer ${token}`,
          accept: "application/json",
        },
      });
    } catch {
      throw new HttpDiagnosticError(503, {
        code: "auth_unavailable",
        message: "인증 서비스를 사용할 수 없습니다.",
        retryable: true,
      });
    }
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        throw new HttpDiagnosticError(401, {
          code: "auth_invalid",
          message: "인증 정보가 유효하지 않습니다.",
          retryable: false,
        });
      }
      throw new HttpDiagnosticError(503, {
        code: "auth_unavailable",
        message: "인증 서비스를 사용할 수 없습니다.",
        retryable: true,
      });
    }

    let payload: AuthUserPayload;
    try {
      payload = await response.json() as AuthUserPayload;
    } catch {
      throw new HttpDiagnosticError(503, {
        code: "auth_unavailable",
        message: "인증 서비스를 사용할 수 없습니다.",
        retryable: true,
      });
    }
    if (typeof payload.id !== "string" || payload.id.length === 0) {
      throw new HttpDiagnosticError(401, {
        code: "auth_invalid",
        message: "인증 정보가 유효하지 않습니다.",
        retryable: false,
      });
    }
    return {
      id: payload.id,
      isAnonymous: payload.is_anonymous === true || payload.app_metadata?.provider === "anonymous",
      accessToken: token,
    };
  }
}
