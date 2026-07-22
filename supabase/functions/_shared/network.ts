import { HttpDiagnosticError } from "./http.ts";

function unavailable(): never {
  throw new HttpDiagnosticError(503, {
    code: "pairing_network_unavailable",
    message: "안전한 네트워크 정보를 확인할 수 없습니다.",
    retryable: true,
  });
}

function canonicalIpv4(value: string): string | undefined {
  const parts = value.split(".");
  if (parts.length !== 4) return undefined;
  const numbers: number[] = [];
  for (const part of parts) {
    if (!/^(0|[1-9][0-9]{0,2})$/.test(part)) return undefined;
    const number = Number(part);
    if (number > 255) return undefined;
    numbers.push(number);
  }
  return numbers.join(".");
}

function canonicalIpv6(value: string): string | undefined {
  if (!value.includes(":") || value.includes("%") || !/^[0-9a-f:.]+$/i.test(value)) {
    return undefined;
  }
  try {
    const hostname = new URL(`http://[${value}]/`).hostname;
    if (!hostname.startsWith("[") || !hostname.endsWith("]")) return undefined;
    return hostname.slice(1, -1).toLowerCase();
  } catch {
    return undefined;
  }
}

/**
 * Supabase's hosted gateway runs behind Cloudflare and supplies the
 * CF-Connecting-IP request metadata used by its own request logs. The gateway
 * must overwrite this header; this function must never be exposed directly or
 * behind a proxy that merely passes through a caller-provided value.
 */
export function trustedGatewayClientAddress(request: Request): string {
  const candidate = request.headers.get("cf-connecting-ip")?.trim() ?? "";
  if (candidate.length === 0 || candidate.length > 64) unavailable();
  return canonicalIpv4(candidate) ?? canonicalIpv6(candidate) ?? unavailable();
}

export async function pairingNetworkDigest(
  secret: string,
  request: Request,
): Promise<Uint8Array> {
  const address = trustedGatewayClientAddress(request);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`pairing-network:v1:${address}`),
    ),
  );
}
