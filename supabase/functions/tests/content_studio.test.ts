import publishedFixture from "../../../content/packages/addition_ones/1.0.0.json" with {
  type: "json",
};
import type {
  ContentDraft,
  ContentPublication,
  ContentPublicationHistoryItem,
  SaveDraftInput,
} from "../../../packages/contracts/src/cloud/wire.ts";
import { saveDraft, type SaveDraftDependencies } from "../save-draft/index.ts";
import { validateDraft, type ValidateDraftDependencies } from "../validate-draft/index.ts";
import { contentHistory, type ContentHistoryDependencies } from "../content-history/index.ts";
import type { ContentStudioRepository } from "../_shared/studio.ts";
import { SupabaseFunctionRepository } from "../_shared/supabase.ts";

const ORIGIN = "https://jinhoofkepco.github.io";
const OWNER_ID = "00000000-0000-4000-8000-000000000301";
const EDITOR_ID = "00000000-0000-4000-8000-000000000302";
const DRAFT_ID = "60000000-0000-4000-8000-000000000301";

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
    ) => [
      key,
      stable(item),
    ]),
  );
}

function draftPackage(): ContentDraft["package"] {
  const clone = structuredClone(publishedFixture) as Record<string, unknown>;
  delete clone.checksum;
  return clone as unknown as ContentDraft["package"];
}

function draftRecord(revision = 3): ContentDraft {
  const packageDraft = draftPackage();
  return {
    id: DRAFT_ID,
    activityId: packageDraft.activity_id,
    title: packageDraft.localizations["ko-KR"].title,
    revision,
    updatedAt: "2026-07-22T04:00:00.000Z",
    package: packageDraft,
  };
}

function historyItem(): ContentPublicationHistoryItem {
  return {
    id: "71000000-0000-4000-8000-000000000301",
    activityId: "addition_ones",
    contentVersion: "1.0.0",
    checksum: `sha256:${"a".repeat(64)}`,
    status: "active",
    publishedAt: "2026-07-22T04:00:00.000Z",
    effectiveAt: "2026-07-22T04:00:00.000Z",
    publishedBy: OWNER_ID,
    sourceRevision: 3,
    rollbackOfId: null,
    reason: "첫 배포",
    validationValid: true,
  };
}

function repository(
  overrides: Partial<ContentStudioRepository> = {},
): ContentStudioRepository {
  return {
    hasRole: (_token, role) => Promise.resolve(role === "owner"),
    getDraft: () => Promise.resolve(draftRecord()),
    saveDraft: (_token, input: SaveDraftInput) =>
      Promise.resolve(draftRecord((input.expectedRevision ?? 0) + 1)),
    commitPublication: () =>
      Promise.resolve({
        publicationId: "71000000-0000-4000-8000-000000000301",
        publishedAt: "2026-07-22T04:00:00.000Z",
        effectiveAt: "2026-07-22T04:00:00.000Z",
        status: "active",
      }),
    getRollbackSource: () => Promise.resolve(undefined),
    listPublicationHistory: () => Promise.resolve([historyItem()]),
    ...overrides,
  };
}

function post(path: string, body: unknown): Request {
  return new Request(`http://localhost/functions/v1/${path}`, {
    method: "POST",
    headers: {
      authorization: "Bearer caller-token",
      "content-type": "application/json",
      origin: ORIGIN,
    },
    body: JSON.stringify(body),
  });
}

async function responseJson(response: Response): Promise<unknown> {
  return await response.json();
}

function saveDependencies(
  overrides: Partial<SaveDraftDependencies> = {},
): SaveDraftDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({ id: EDITOR_ID, isAnonymous: false, accessToken: "caller-token" }),
    },
    repository: repository({
      hasRole: (_token, role) => Promise.resolve(role === "editor"),
    }),
    requestId: () => "request-save",
    ...overrides,
  };
}

function validateDependencies(
  overrides: Partial<ValidateDraftDependencies> = {},
): ValidateDraftDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({ id: EDITOR_ID, isAnonymous: false, accessToken: "caller-token" }),
    },
    repository: repository({
      hasRole: (_token, role) => Promise.resolve(role === "editor"),
    }),
    requestId: () => "request-validate",
    ...overrides,
  };
}

function historyDependencies(
  overrides: Partial<ContentHistoryDependencies> = {},
): ContentHistoryDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({ id: OWNER_ID, isAnonymous: false, accessToken: "caller-token" }),
    },
    repository: repository(),
    requestId: () => "request-history",
    ...overrides,
  };
}

Deno.test("save-draft accepts an editor optimistic update and returns exact web wire JSON", async () => {
  let observed: SaveDraftInput | undefined;
  const input: SaveDraftInput = {
    draftId: DRAFT_ID,
    expectedRevision: 3,
    package: draftPackage(),
  };
  const response = await saveDraft(
    post("save-draft", input),
    saveDependencies({
      repository: repository({
        hasRole: (_token, role) => Promise.resolve(role === "editor"),
        saveDraft: (_token, value) => {
          observed = value;
          return Promise.resolve(draftRecord(4));
        },
      }),
    }),
  );
  const payload = await responseJson(response);

  assertEquals(response.status, 200);
  assertEquals(payload, draftRecord(4));
  assert(!JSON.stringify(payload).includes("request_id"), "strict wire response gained extra keys");
  assertEquals(observed, input);
  assertEquals(response.headers.get("x-request-id"), "request-save");
});

Deno.test("save-draft rejects a stale expected revision without leaking SQL detail", async () => {
  const response = await saveDraft(
    post("save-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 2,
      package: draftPackage(),
    }),
    saveDependencies({
      repository: repository({
        hasRole: (_token, role) => Promise.resolve(role === "editor"),
        saveDraft: () => Promise.reject({ code: "draft_revision_conflict", detail: "row 42" }),
      }),
    }),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 409);
  assertEquals((payload.error as Record<string, unknown>).code, "draft_revision_conflict");
  assert(!JSON.stringify(payload).includes("row 42"));
});

Deno.test("save-draft rejects guardian access and never writes", async () => {
  let wrote = false;
  const response = await saveDraft(
    post("save-draft", { package: draftPackage() }),
    saveDependencies({
      repository: repository({
        hasRole: () => Promise.resolve(false),
        saveDraft: () => {
          wrote = true;
          return Promise.resolve(draftRecord());
        },
      }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(
    ((await responseJson(response) as Record<string, unknown>).error as Record<string, unknown>)
      .code,
    "studio_role_required",
  );
  assertEquals(wrote, false);
});

Deno.test("save-draft rejects unknown body keys before repository access", async () => {
  let called = false;
  const response = await saveDraft(
    post("save-draft", { package: draftPackage(), overwrite: true }),
    saveDependencies({
      repository: repository({
        hasRole: (_token, role) => Promise.resolve(role === "editor"),
        saveDraft: () => {
          called = true;
          return Promise.resolve(draftRecord());
        },
      }),
    }),
  );

  assertEquals(response.status, 400);
  assertEquals(called, false);
});

Deno.test("validate-draft validates an unsaved package independently without mutating it", async () => {
  const input = draftPackage();
  const before = JSON.stringify(input);
  const response = await validateDraft(
    post("validate-draft", { draftId: DRAFT_ID, package: input }),
    validateDependencies(),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 200);
  assertEquals(payload.valid, true);
  assertEquals(payload.issues, []);
  assertEquals((payload.samples as unknown[]).length, 12);
  assertEquals(JSON.stringify(input), before);
  assert(!JSON.stringify(payload).includes("request_id"));
});

Deno.test("validate-draft returns semantic issues as a typed successful report", async () => {
  const input = draftPackage();
  input.run.combo_thresholds = [4, 4, 7];
  const response = await validateDraft(
    post("validate-draft", { draftId: DRAFT_ID, package: input }),
    validateDependencies(),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 200);
  assertEquals(payload.valid, false);
  assert(
    (payload.issues as Array<Record<string, unknown>>).some((issue) =>
      issue.code === "COMBO_THRESHOLDS"
    ),
  );
});

Deno.test("validate-draft rejects a package for a different stored activity", async () => {
  const input = draftPackage();
  input.activity_id = "subtraction_ones";
  input.icon_id = "subtraction_ones";
  const response = await validateDraft(
    post("validate-draft", { draftId: DRAFT_ID, package: input }),
    validateDependencies(),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 200);
  assertEquals(payload.valid, false);
  assert(
    (payload.issues as Array<Record<string, unknown>>).some((issue) =>
      issue.code === "DRAFT_ACTIVITY_MISMATCH"
    ),
  );
});

Deno.test("content-history requires owner and returns exact history wire array", async () => {
  let activity: string | undefined;
  const response = await contentHistory(
    post("content-history", { activityId: "addition_ones" }),
    historyDependencies({
      repository: repository({
        listPublicationHistory: (_token, activityId) => {
          activity = activityId;
          return Promise.resolve([historyItem()]);
        },
      }),
    }),
  );
  const payload = await responseJson(response);

  assertEquals(response.status, 200);
  assertEquals(payload, [historyItem()]);
  assertEquals(activity, "addition_ones");
  assert(!JSON.stringify(payload).includes("request_id"));
});

Deno.test("content-history supports the web all-activities request", async () => {
  let activity: string | undefined = "unexpected";
  const response = await contentHistory(
    post("content-history", {}),
    historyDependencies({
      repository: repository({
        listPublicationHistory: (_token, activityId) => {
          activity = activityId;
          return Promise.resolve([historyItem()]);
        },
      }),
    }),
  );

  assertEquals(response.status, 200);
  assertEquals(activity, undefined);
});

Deno.test("content-history rejects editors before history access", async () => {
  let called = false;
  const response = await contentHistory(
    post("content-history", {}),
    historyDependencies({
      repository: repository({
        hasRole: () => Promise.resolve(false),
        listPublicationHistory: () => {
          called = true;
          return Promise.resolve([]);
        },
      }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(called, false);
});

Deno.test("Studio role checks call the global-only authorization RPC", async () => {
  let observedName: string | undefined;
  let observedBody: Record<string, unknown> | undefined;
  const caller = {
    call: (name: string, _accessToken: string, body: Record<string, unknown>) => {
      observedName = name;
      observedBody = body;
      return Promise.resolve(false);
    },
  };
  const repository = new SupabaseFunctionRepository({} as never, caller as never);

  assertEquals(await repository.hasRole("caller-token", "owner"), false);
  assertEquals(observedName, "has_global_studio_role");
  assertEquals(observedBody, { required_role: "owner" });
});

Deno.test("publication commits map the database-authoritative lifecycle row", async () => {
  let observedName: string | undefined;
  let observedBody: Record<string, unknown> | undefined;
  const service = {
    call: (name: string, body: Record<string, unknown>) => {
      observedName = name;
      observedBody = body;
      return Promise.resolve([{
        publication_id: "71000000-0000-4000-8000-000000000301",
        published_at: "2026-07-22T04:00:05.000Z",
        effective_at: "2026-07-22T04:00:05.000Z",
        status: "active",
      }]);
    },
  };
  const repository = new SupabaseFunctionRepository(service as never, {} as never);
  const packageValue = structuredClone(
    publishedFixture,
  ) as unknown as ContentPublication["package"];

  const result = await repository.commitPublication({
    draftId: DRAFT_ID,
    expectedRevision: 3,
    publishedPackage: packageValue,
    checksum: packageValue.checksum,
    validationReport: { valid: true, issues: [], samples: [] },
    actorUserId: OWNER_ID,
    effectiveAt: null,
    requestId: "81000000-0000-4000-8000-000000000301",
    reason: "DB 시각 매핑",
    rollbackPublicationId: null,
  });

  assertEquals(observedName, "commit_validated_content_publication_v2");
  assertEquals(observedBody?.target_effective_at, null);
  assertEquals(result, {
    publicationId: "71000000-0000-4000-8000-000000000301",
    publishedAt: "2026-07-22T04:00:05.000Z",
    effectiveAt: "2026-07-22T04:00:05.000Z",
    status: "active",
  });
});
