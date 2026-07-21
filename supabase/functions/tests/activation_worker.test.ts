import {
  activatePublications,
  type ActivatePublicationsDependencies,
} from "../activate-publications/index.ts";
import type { PublicationActivationRepository } from "../_shared/scheduler.ts";
import { SupabaseFunctionRepository } from "../_shared/supabase.ts";

const SCHEDULER_SECRET = "scheduler-secret-that-is-at-least-32-bytes";
const PUBLICATION_IDS = [
  "71000000-0000-4000-8000-000000000301",
  "71000000-0000-4000-8000-000000000302",
];

function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  const actualJson = JSON.stringify(stable(actual));
  const expectedJson = JSON.stringify(stable(expected));
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, received ${actualJson}`);
  }
}

function stable(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stable);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.entries(value).sort(([left], [right]) => left.localeCompare(right)).map((
      [key, item],
    ) => [key, stable(item)]),
  );
}

function repository(
  overrides: Partial<PublicationActivationRepository> = {},
): PublicationActivationRepository {
  return {
    listDuePublicationIds: () => Promise.resolve([...PUBLICATION_IDS]),
    activatePublication: (publicationId) => Promise.resolve(publicationId),
    ...overrides,
  };
}

function dependencies(
  overrides: Partial<ActivatePublicationsDependencies> = {},
): ActivatePublicationsDependencies {
  let operation = 0;
  return {
    schedulerSecret: SCHEDULER_SECRET,
    repository: repository(),
    operationId: () => `81000000-0000-4000-8000-${String(++operation).padStart(12, "0")}`,
    requestId: () => "request-activate-publications",
    ...overrides,
  };
}

function post(
  body: string | Record<string, unknown> = {},
  token: string | null = SCHEDULER_SECRET,
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (token !== null) headers.set("authorization", `Bearer ${token}`);
  return new Request("http://localhost/functions/v1/activate-publications", {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

Deno.test("activation worker rejects missing and incorrect scheduler credentials before parsing", async () => {
  let called = false;
  const workerDependencies = dependencies({
    repository: repository({
      listDuePublicationIds: () => {
        called = true;
        return Promise.resolve([]);
      },
    }),
  });

  for (const token of [null, "incorrect-secret-that-is-at-least-32-bytes"]) {
    const response = await activatePublications(post("{invalid-json", token), workerDependencies);
    const payload = await responseJson(response);

    assertEquals(response.status, 401);
    assertEquals((payload.error as Record<string, unknown>).code, "scheduler_auth_invalid");
    assert(!JSON.stringify(payload).includes("invalid_json"));
  }
  assertEquals(called, false);
});

Deno.test("activation worker rejects malformed or unbounded request bodies before queue access", async () => {
  let called = false;
  const workerDependencies = dependencies({
    repository: repository({
      listDuePublicationIds: () => {
        called = true;
        return Promise.resolve([]);
      },
    }),
  });

  for (
    const body of ["{invalid-json", { batchLimit: 0 }, { batchLimit: 101 }, {
      batchLimit: 1,
      unbounded: true,
    }]
  ) {
    const response = await activatePublications(post(body), workerDependencies);
    assertEquals(response.status, 400);
  }
  assertEquals(called, false);
});

Deno.test("activation worker reads a bounded due batch and activates each publication once", async () => {
  let observedLimit: number | undefined;
  const activations: Array<{ publicationId: string; requestId: string }> = [];
  const response = await activatePublications(
    post({ batchLimit: 2 }),
    dependencies({
      repository: repository({
        listDuePublicationIds: (limit) => {
          observedLimit = limit;
          return Promise.resolve([...PUBLICATION_IDS]);
        },
        activatePublication: (publicationId, requestId) => {
          activations.push({ publicationId, requestId });
          return Promise.resolve(publicationId);
        },
      }),
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await responseJson(response), {
    processed: 2,
    publicationIds: PUBLICATION_IDS,
  });
  assertEquals(observedLimit, 2);
  assertEquals(activations, [
    {
      publicationId: PUBLICATION_IDS[0],
      requestId: "81000000-0000-4000-8000-000000000001",
    },
    {
      publicationId: PUBLICATION_IDS[1],
      requestId: "81000000-0000-4000-8000-000000000002",
    },
  ]);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("x-request-id"), "request-activate-publications");
});

Deno.test("activation worker defaults to a bounded batch and empty retries are successful", async () => {
  let observedLimit: number | undefined;
  const response = await activatePublications(
    post({}),
    dependencies({
      repository: repository({
        listDuePublicationIds: (limit) => {
          observedLimit = limit;
          return Promise.resolve([]);
        },
      }),
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(await responseJson(response), { processed: 0, publicationIds: [] });
  assertEquals(observedLimit, 25);
});

Deno.test("activation worker relies on idempotent database activation across concurrent runs", async () => {
  const activated = new Set<string>();
  let auditWrites = 0;
  const sharedRepository = repository({
    listDuePublicationIds: () => Promise.resolve([PUBLICATION_IDS[0]]),
    activatePublication: async (publicationId) => {
      await Promise.resolve();
      if (!activated.has(publicationId)) {
        activated.add(publicationId);
        auditWrites += 1;
      }
      return publicationId;
    },
  });

  const responses = await Promise.all([
    activatePublications(post({ batchLimit: 1 }), dependencies({ repository: sharedRepository })),
    activatePublications(post({ batchLimit: 1 }), dependencies({ repository: sharedRepository })),
  ]);

  assertEquals(responses.map((response) => response.status), [200, 200]);
  assertEquals(auditWrites, 1);
});

Deno.test("activation worker returns a generic retryable failure without upstream detail", async () => {
  const response = await activatePublications(
    post({}),
    dependencies({
      repository: repository({
        listDuePublicationIds: () =>
          Promise.reject({
            code: "42501",
            details: "service_role cannot scan row 42",
          }),
      }),
    }),
  );
  const payload = await responseJson(response);

  assertEquals(response.status, 503);
  assertEquals((payload.error as Record<string, unknown>).code, "activation_service_unavailable");
  assertEquals((payload.error as Record<string, unknown>).retryable, true);
  assert(!JSON.stringify(payload).includes("row 42"));
});

Deno.test("activation repository maps only the bounded queue and idempotent activation RPCs", async () => {
  const calls: Array<{ name: string; body: Record<string, unknown> }> = [];
  const service = {
    call: (name: string, body: Record<string, unknown>) => {
      calls.push({ name, body });
      if (name === "get_due_content_publication_ids") {
        return Promise.resolve(PUBLICATION_IDS.map((publication_id) => ({ publication_id })));
      }
      return Promise.resolve(PUBLICATION_IDS[0]);
    },
  };
  const repository = new SupabaseFunctionRepository(service as never, {} as never);

  assertEquals(await repository.listDuePublicationIds(2), PUBLICATION_IDS);
  assertEquals(
    await repository.activatePublication(
      PUBLICATION_IDS[0],
      "81000000-0000-4000-8000-000000000099",
    ),
    PUBLICATION_IDS[0],
  );
  assertEquals(calls, [
    { name: "get_due_content_publication_ids", body: { batch_limit: 2 } },
    {
      name: "activate_due_content_publication",
      body: {
        target_publication_id: PUBLICATION_IDS[0],
        activation_request_id: "81000000-0000-4000-8000-000000000099",
      },
    },
  ]);
});
