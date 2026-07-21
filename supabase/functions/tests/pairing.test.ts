import {
  createPairingCode,
  type CreatePairingCodeDependencies,
} from "../create-pairing-code/index.ts";
import { pairDevice, type PairDeviceDependencies } from "../pair-device/index.ts";
import { SupabaseAuthVerifier } from "../_shared/auth.ts";

const ORIGIN = "https://jinhoofkepco.github.io";
const NOW = new Date("2026-07-22T03:00:00.000Z");
const GUARDIAN_ID = "00000000-0000-4000-8000-000000000101";
const DEVICE_USER_ID = "00000000-0000-4000-8000-000000000102";
const PROFILE_ID = "20000000-0000-4000-8000-000000000101";
const FAMILY_ID = "10000000-0000-4000-8000-000000000101";
const PAIRING_ID = "30000000-0000-4000-8000-000000000101";
const DEVICE_ROW_ID = "40000000-0000-4000-8000-000000000101";
const SECRET = "test-only-pairing-hmac-secret-at-least-32-bytes";

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, received ${actualJson}`);
  }
}

async function json(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

function bearerRequest(path: string, body: unknown, origin = ORIGIN): Request {
  return new Request(`http://localhost/functions/v1/${path}`, {
    method: "POST",
    headers: {
      authorization: "Bearer valid-token",
      "content-type": "application/json",
      origin,
    },
    body: JSON.stringify(body),
  });
}

function guardianDependencies(
  overrides: Partial<CreatePairingCodeDependencies> = {},
): CreatePairingCodeDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({
          id: GUARDIAN_ID,
          isAnonymous: false,
        }),
    },
    clock: { now: () => new Date(NOW) },
    codeGenerator: () => "123456",
    pairingSecret: SECRET,
    repository: {
      createChallenge: () => Promise.resolve(PAIRING_ID),
    },
    requestId: () => "request-create",
    ...overrides,
  };
}

function deviceDependencies(
  overrides: Partial<PairDeviceDependencies> = {},
): PairDeviceDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({
          id: DEVICE_USER_ID,
          isAnonymous: true,
        }),
    },
    pairingSecret: SECRET,
    repository: {
      claimChallenge: () =>
        Promise.resolve({
          outcome: "paired" as const,
          deviceId: DEVICE_ROW_ID,
          familyId: FAMILY_ID,
          profileId: PROFILE_ID,
          profileLocalId: "profile-pairing",
        }),
    },
    requestId: () => "request-pair",
    ...overrides,
  };
}

Deno.test("Supabase auth verification forwards only the publishable key and caller bearer", async () => {
  let observedUrl = "";
  let observedHeaders = new Headers();
  const verifier = new SupabaseAuthVerifier(
    "https://project.supabase.co",
    "sb_publishable_test",
    (input, init) => {
      observedUrl = String(input);
      observedHeaders = new Headers(init?.headers);
      return Promise.resolve(
        Response.json({
          id: DEVICE_USER_ID,
          is_anonymous: true,
          app_metadata: { provider: "anonymous" },
        }),
      );
    },
  );

  const identity = await verifier.verifyBearer(
    new Request("http://localhost", {
      headers: { authorization: "Bearer caller-token" },
    }),
  );

  assertEquals(observedUrl, "https://project.supabase.co/auth/v1/user");
  assertEquals(observedHeaders.get("apikey"), "sb_publishable_test");
  assertEquals(observedHeaders.get("authorization"), "Bearer caller-token");
  assertEquals(identity.id, DEVICE_USER_ID);
  assertEquals(identity.isAnonymous, true);
  assertEquals(identity.accessToken, "caller-token");
  assert(!JSON.stringify([...observedHeaders]).includes("service_role"));
});

Deno.test("Supabase auth verification rejects missing bearer before network access", async () => {
  let called = false;
  const verifier = new SupabaseAuthVerifier(
    "https://project.supabase.co",
    "sb_publishable_test",
    () => {
      called = true;
      return Promise.resolve(Response.json({}));
    },
  );

  let code = "";
  try {
    await verifier.verifyBearer(new Request("http://localhost"));
  } catch (error) {
    code = typeof error === "object" && error !== null && "diagnostic" in error
      ? String((error.diagnostic as Record<string, unknown>).code)
      : "unexpected";
  }
  assertEquals(code, "auth_required");
  assertEquals(called, false);
});

Deno.test("create pairing code requires a bearer token", async () => {
  const deps = guardianDependencies({
    auth: {
      verifyBearer: () => Promise.reject({ code: "auth_required" }),
    },
  });
  const response = await createPairingCode(
    new Request("http://localhost/functions/v1/create-pairing-code", {
      method: "POST",
      headers: { "content-type": "application/json", origin: ORIGIN },
      body: JSON.stringify({ profile_id: PROFILE_ID }),
    }),
    deps,
  );

  assertEquals(response.status, 401);
  assertEquals((await json(response)).error, {
    code: "auth_required",
    message: "인증이 필요합니다.",
    retryable: false,
  });
});

Deno.test("create pairing code rejects anonymous device identities", async () => {
  const response = await createPairingCode(
    bearerRequest("create-pairing-code", { profile_id: PROFILE_ID }),
    guardianDependencies({
      auth: {
        verifyBearer: () => Promise.resolve({ id: DEVICE_USER_ID, isAnonymous: true }),
      },
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(((await json(response)).error as Record<string, unknown>).code, "guardian_required");
});

Deno.test("create pairing code stores only an HMAC digest and expires in ten minutes", async () => {
  let captured:
    | {
      profileId: string;
      digest: Uint8Array;
      expiresAt: Date;
      actorUserId: string;
    }
    | undefined;
  const response = await createPairingCode(
    bearerRequest("create-pairing-code", { profile_id: PROFILE_ID }),
    guardianDependencies({
      repository: {
        createChallenge: (input) => {
          captured = input;
          return Promise.resolve(PAIRING_ID);
        },
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 201);
  assertEquals(payload.code, "123456");
  assertEquals(payload.expires_at, "2026-07-22T03:10:00.000Z");
  assertEquals(payload.request_id, "request-create");
  assert(captured !== undefined);
  assertEquals(captured.profileId, PROFILE_ID);
  assertEquals(captured.actorUserId, GUARDIAN_ID);
  assertEquals(captured.expiresAt.toISOString(), "2026-07-22T03:10:00.000Z");
  assertEquals(captured.digest.byteLength, 32);
  assert(!new TextDecoder().decode(captured.digest).includes("123456"), "plaintext code leaked");

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode("123456")),
  );
  assertEquals(Array.from(captured.digest), Array.from(expected));
});

Deno.test("create pairing code returns a permission diagnostic without database detail", async () => {
  const response = await createPairingCode(
    bearerRequest("create-pairing-code", { profile_id: PROFILE_ID }),
    guardianDependencies({
      repository: {
        createChallenge: () => Promise.reject({ code: "42501", message: "secret row detail" }),
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 403);
  assertEquals((payload.error as Record<string, unknown>).code, "profile_access_denied");
  assert(!JSON.stringify(payload).includes("secret row detail"));
  assert(!JSON.stringify(payload).includes("stack"));
});

Deno.test("pair device requires an anonymous Auth identity", async () => {
  const response = await pairDevice(
    bearerRequest("pair-device", {
      code: "123456",
      device_id: "device-pairing",
      display_name: "MathLand Android",
    }),
    deviceDependencies({
      auth: {
        verifyBearer: () => Promise.resolve({ id: GUARDIAN_ID, isAnonymous: false }),
      },
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "anonymous_device_required",
  );
});

Deno.test("pair device rejects a blank display name before repository access", async () => {
  let called = false;
  const response = await pairDevice(
    bearerRequest("pair-device", {
      code: "123456",
      device_id: "device-pairing",
      display_name: "   ",
    }),
    deviceDependencies({
      repository: {
        claimChallenge: () => {
          called = true;
          return Promise.reject(new Error("must not be called"));
        },
      },
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "invalid_pairing_request",
  );
  assertEquals(called, false);
});

Deno.test("pair device hashes the code and returns only non-sensitive binding identifiers", async () => {
  let captured:
    | {
      digest: Uint8Array;
      deviceAuthUserId: string;
      deviceIdentifier: string;
      displayName: string;
    }
    | undefined;
  const response = await pairDevice(
    bearerRequest("pair-device", {
      code: "123456",
      device_id: "device-pairing",
      display_name: "My phone",
    }),
    deviceDependencies({
      repository: {
        claimChallenge: (input) => {
          captured = input;
          return Promise.resolve({
            outcome: "paired",
            deviceId: DEVICE_ROW_ID,
            familyId: FAMILY_ID,
            profileId: PROFILE_ID,
            profileLocalId: "profile-pairing",
          });
        },
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 200);
  assertEquals(payload, {
    device_id: DEVICE_ROW_ID,
    family_id: FAMILY_ID,
    profile_id: PROFILE_ID,
    profile_local_id: "profile-pairing",
    request_id: "request-pair",
  });
  assert(captured !== undefined);
  assertEquals(captured.deviceAuthUserId, DEVICE_USER_ID);
  assertEquals(captured.deviceIdentifier, "device-pairing");
  assertEquals(captured.displayName, "My phone");
  assertEquals(captured.digest.byteLength, 32);
});

for (const outcome of ["missing", "expired", "used", "wrong"] as const) {
  Deno.test(`pair device hides the ${outcome} code state`, async () => {
    const response = await pairDevice(
      bearerRequest("pair-device", {
        code: "123456",
        device_id: "device-pairing",
      }),
      deviceDependencies({
        repository: {
          claimChallenge: () => Promise.resolve({ outcome }),
        },
      }),
    );
    const payload = await json(response);

    assertEquals(response.status, 400);
    assertEquals((payload.error as Record<string, unknown>).code, "pairing_code_invalid");
    assert(!JSON.stringify(payload).includes(outcome));
  });
}

Deno.test("pair device rejects a second profile binding", async () => {
  const response = await pairDevice(
    bearerRequest("pair-device", { code: "123456", device_id: "device-pairing" }),
    deviceDependencies({
      repository: {
        claimChallenge: () => Promise.resolve({ outcome: "device_already_paired" }),
      },
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "device_already_paired",
  );
});

Deno.test("pair device returns a stable rate-limit diagnostic", async () => {
  const response = await pairDevice(
    bearerRequest("pair-device", { code: "123456", device_id: "device-pairing" }),
    deviceDependencies({
      repository: {
        claimChallenge: () => Promise.resolve({ outcome: "rate_limited" }),
      },
    }),
  );

  assertEquals(response.status, 429);
  assertEquals((await json(response)).error, {
    code: "pairing_rate_limited",
    message: "잠시 후 다시 시도해 주세요.",
    retryable: true,
  });
});

Deno.test("pair device fails closed when the persistent claim boundary is unavailable", async () => {
  const response = await pairDevice(
    bearerRequest("pair-device", { code: "123456", device_id: "device-pairing" }),
    deviceDependencies({
      repository: {
        claimChallenge: () => Promise.reject(new Error("database offline\nsecret stack")),
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 503);
  assertEquals((payload.error as Record<string, unknown>).code, "pairing_service_unavailable");
  assertEquals((payload.error as Record<string, unknown>).retryable, true);
  assert(!JSON.stringify(payload).includes("database offline"));
  assert(!JSON.stringify(payload).includes("stack"));
});

Deno.test("pairing handlers deny an origin outside the explicit allowlist", async () => {
  const response = await createPairingCode(
    bearerRequest(
      "create-pairing-code",
      { profile_id: PROFILE_ID },
      "https://attacker.invalid",
    ),
    guardianDependencies(),
  );

  assertEquals(response.status, 403);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "cors_origin_denied",
  );
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});

Deno.test("pairing preflight reflects only an explicitly allowed origin", async () => {
  const response = await pairDevice(
    new Request("http://localhost/functions/v1/pair-device", {
      method: "OPTIONS",
      headers: { origin: ORIGIN, "access-control-request-method": "POST" },
    }),
    deviceDependencies(),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), ORIGIN);
  assertEquals(response.headers.get("vary"), "Origin");
});
