import { ingestEvents, type IngestEventsDependencies } from "../ingest-events/index.ts";

const ORIGIN = "https://jinhoofkepco.github.io";
const DEVICE_USER_ID = "00000000-0000-4000-8000-000000000102";

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

function event(
  sequence: number,
  eventId = `50000000-0000-4000-8000-${String(sequence).padStart(12, "0")}`,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    contract_version: 1,
    event_id: eventId,
    profile_id: "profile-pairing",
    device_id: "device-pairing",
    sequence,
    client_timestamp: "2026-07-22T03:00:00Z",
    event_type: "collection_unlocked",
    collection_id: `collection-${sequence}`,
    ...overrides,
  };
}

function request(body: string | Record<string, unknown>): Request {
  return new Request("http://localhost/functions/v1/ingest-events", {
    method: "POST",
    headers: {
      authorization: "Bearer valid-token",
      "content-type": "application/json",
      origin: ORIGIN,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function dependencies(
  overrides: Partial<IngestEventsDependencies> = {},
): IngestEventsDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () => Promise.resolve({ id: DEVICE_USER_ID, isAnonymous: true }),
    },
    repository: {
      ingest: (_userId, events) =>
        Promise.resolve({
          acceptedEventIds: events.map((item) => item.event_id),
          alreadyPresentEventIds: [],
          serverCursor: String(events.at(-1)?.sequence ?? 0),
        }),
    },
    requestId: () => "request-ingest",
    ...overrides,
  };
}

Deno.test("ingestion requires bearer authentication", async () => {
  const response = await ingestEvents(
    request({ events: [event(1)] }),
    dependencies({
      auth: { verifyBearer: () => Promise.reject({ code: "auth_invalid" }) },
    }),
  );

  assertEquals(response.status, 401);
  assertEquals(((await json(response)).error as Record<string, unknown>).code, "auth_invalid");
});

Deno.test("ingestion accepts only anonymous device identities", async () => {
  const response = await ingestEvents(
    request({ events: [event(1)] }),
    dependencies({
      auth: {
        verifyBearer: () => Promise.resolve({ id: DEVICE_USER_ID, isAnonymous: false }),
      },
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "anonymous_device_required",
  );
});

Deno.test("ingestion rejects malformed JSON with a stable contract code", async () => {
  const response = await ingestEvents(request("{"), dependencies());

  assertEquals(response.status, 400);
  assertEquals(((await json(response)).error as Record<string, unknown>).code, "invalid_json");
});

Deno.test("ingestion rejects an empty batch", async () => {
  const response = await ingestEvents(request({ events: [] }), dependencies());

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "invalid_event_batch",
  );
});

Deno.test("ingestion rejects more than one hundred events", async () => {
  const response = await ingestEvents(
    request({ events: Array.from({ length: 101 }, (_, index) => event(index + 1)) }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "invalid_event_batch",
  );
});

Deno.test("ingestion validates every LearningEventV1 before repository access", async () => {
  let called = false;
  const response = await ingestEvents(
    request({ events: [event(1, undefined, { unknown_field: "reject me" })] }),
    dependencies({
      repository: {
        ingest: () => {
          called = true;
          return Promise.reject(new Error("must not be called"));
        },
      },
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "invalid_event_schema",
  );
  assertEquals(called, false);
});

Deno.test("ingestion rejects non-increasing event sequences", async () => {
  const response = await ingestEvents(
    request({ events: [event(2), event(1)] }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "event_sequence_invalid",
  );
});

Deno.test("ingestion rejects mixed device or profile identifiers", async () => {
  for (
    const mismatch of [
      event(2, undefined, { device_id: "other-device" }),
      event(2, undefined, { profile_id: "other-profile" }),
    ]
  ) {
    const response = await ingestEvents(
      request({ events: [event(1), mismatch] }),
      dependencies(),
    );
    assertEquals(response.status, 400);
    assertEquals(
      ((await json(response)).error as Record<string, unknown>).code,
      "event_binding_inconsistent",
    );
  }
});

Deno.test("ingestion rejects duplicate event IDs within one batch", async () => {
  const duplicateId = "50000000-0000-4000-8000-000000000099";
  const response = await ingestEvents(
    request({ events: [event(1, duplicateId), event(2, duplicateId)] }),
    dependencies(),
  );

  assertEquals(response.status, 400);
  assertEquals(
    ((await json(response)).error as Record<string, unknown>).code,
    "duplicate_event_id",
  );
});

Deno.test("ingestion returns mixed accepted and already-present IDs with an authoritative cursor", async () => {
  const acceptedId = "50000000-0000-4000-8000-000000000001";
  const replayedId = "50000000-0000-4000-8000-000000000002";
  const response = await ingestEvents(
    request({ events: [event(1, acceptedId), event(2, replayedId)] }),
    dependencies({
      repository: {
        ingest: () =>
          Promise.resolve({
            acceptedEventIds: [acceptedId],
            alreadyPresentEventIds: [replayedId],
            serverCursor: "42",
          }),
      },
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await json(response), {
    accepted_event_ids: [acceptedId],
    already_present_event_ids: [replayedId],
    server_cursor: "42",
    request_id: "request-ingest",
  });
});

Deno.test("ingestion exposes a non-retryable permission code without SQL detail", async () => {
  const response = await ingestEvents(
    request({ events: [event(1)] }),
    dependencies({
      repository: {
        ingest: () => Promise.reject({ code: "42501", message: "private binding detail" }),
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 403);
  assertEquals((payload.error as Record<string, unknown>).code, "device_binding_denied");
  assertEquals((payload.error as Record<string, unknown>).retryable, false);
  assert(!JSON.stringify(payload).includes("private binding detail"));
});

Deno.test("ingestion exposes an event-ID collision as a non-retryable conflict", async () => {
  const response = await ingestEvents(
    request({ events: [event(1)] }),
    dependencies({
      repository: {
        ingest: () => Promise.reject({ code: "23505", message: "payload differs" }),
      },
    }),
  );

  assertEquals(response.status, 409);
  assertEquals(((await json(response)).error as Record<string, unknown>).code, "event_id_conflict");
});

Deno.test("ingestion error envelopes include request IDs and never leak stacks", async () => {
  const response = await ingestEvents(
    request({ events: [event(1)] }),
    dependencies({
      repository: {
        ingest: () => Promise.reject(new Error("network secret\nstack secret")),
      },
    }),
  );
  const payload = await json(response);

  assertEquals(response.status, 503);
  assertEquals(payload.request_id, "request-ingest");
  assertEquals((payload.error as Record<string, unknown>).code, "ingest_service_unavailable");
  assert((payload.error as Record<string, unknown>).retryable === true);
  assert(!JSON.stringify(payload).includes("network secret"));
  assert(!JSON.stringify(payload).includes("stack secret"));
});
