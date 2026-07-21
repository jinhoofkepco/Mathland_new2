export type Diagnostic = {
  code: string;
  message: string;
  retryable: boolean;
};

export class HttpDiagnosticError extends Error {
  readonly status: number;
  readonly diagnostic: Diagnostic;

  constructor(status: number, diagnostic: Diagnostic) {
    super(diagnostic.code);
    this.name = "HttpDiagnosticError";
    this.status = status;
    this.diagnostic = diagnostic;
  }
}

export type RequestContext = {
  requestId: string;
  headers: Headers;
  earlyResponse?: Response;
};

const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export function resolveRequestId(request: Request, fallback: () => string): string {
  const supplied = request.headers.get("x-request-id");
  return supplied !== null && REQUEST_ID_PATTERN.test(supplied) ? supplied : fallback();
}

export function prepareRequest(
  request: Request,
  allowedOrigins: readonly string[],
  fallbackRequestId: () => string,
): RequestContext {
  const requestId = resolveRequestId(request, fallbackRequestId);
  const origin = request.headers.get("origin");
  const headers = new Headers({
    "cache-control": "no-store",
    "x-request-id": requestId,
  });

  if (origin !== null) {
    if (!allowedOrigins.includes(origin)) {
      return {
        requestId,
        headers,
        earlyResponse: errorResponse(
          requestId,
          403,
          {
            code: "cors_origin_denied",
            message: "허용되지 않은 요청 출처입니다.",
            retryable: false,
          },
          headers,
        ),
      };
    }
    headers.set("access-control-allow-origin", origin);
    headers.set("access-control-allow-methods", "POST, OPTIONS");
    headers.set(
      "access-control-allow-headers",
      "authorization, apikey, content-type, x-client-info, x-request-id",
    );
    headers.set("access-control-max-age", "600");
    headers.set("vary", "Origin");
  }

  if (request.method === "OPTIONS") {
    return {
      requestId,
      headers,
      earlyResponse: new Response(null, { status: 204, headers }),
    };
  }
  if (request.method !== "POST") {
    return {
      requestId,
      headers,
      earlyResponse: errorResponse(
        requestId,
        405,
        {
          code: "method_not_allowed",
          message: "POST 요청만 사용할 수 있습니다.",
          retryable: false,
        },
        headers,
      ),
    };
  }
  return { requestId, headers };
}

export function successResponse(
  requestId: string,
  status: number,
  data: Record<string, unknown>,
  baseHeaders: Headers,
): Response {
  const headers = new Headers(baseHeaders);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify({ ...data, request_id: requestId }), { status, headers });
}

/** Returns an exact public wire value while keeping correlation metadata in headers. */
export function wireResponse(
  status: number,
  data: unknown,
  baseHeaders: Headers,
): Response {
  const headers = new Headers(baseHeaders);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data), { status, headers });
}

export function errorResponse(
  requestId: string,
  status: number,
  diagnostic: Diagnostic,
  baseHeaders: Headers,
): Response {
  const headers = new Headers(baseHeaders);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify({ error: diagnostic, request_id: requestId }), {
    status,
    headers,
  });
}

export async function readJson(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new HttpDiagnosticError(415, {
      code: "content_type_required",
      message: "JSON 요청이 필요합니다.",
      retryable: false,
    });
  }
  try {
    return await request.json();
  } catch {
    throw new HttpDiagnosticError(400, {
      code: "invalid_json",
      message: "JSON 형식이 올바르지 않습니다.",
      retryable: false,
    });
  }
}

export function knownDiagnostic(error: unknown): HttpDiagnosticError | undefined {
  if (error instanceof HttpDiagnosticError) return error;
  if (typeof error !== "object" || error === null || !("code" in error)) return undefined;
  const code = String(error.code);
  if (code === "auth_required") {
    return new HttpDiagnosticError(401, {
      code,
      message: "인증이 필요합니다.",
      retryable: false,
    });
  }
  if (code === "auth_invalid") {
    return new HttpDiagnosticError(401, {
      code,
      message: "인증 정보가 유효하지 않습니다.",
      retryable: false,
    });
  }
  if (code === "auth_unavailable") {
    return new HttpDiagnosticError(503, {
      code,
      message: "인증 서비스를 사용할 수 없습니다.",
      retryable: true,
    });
  }
  return undefined;
}

export function unexpectedError(
  requestId: string,
  code: string,
  message: string,
  headers: Headers,
): Response {
  return errorResponse(
    requestId,
    503,
    { code, message, retryable: true },
    headers,
  );
}
