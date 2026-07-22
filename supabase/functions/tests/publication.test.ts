import publishedFixture from "../../../content/packages/addition_ones/1.0.0.json" with {
  type: "json",
};
import type {
  ContentDraft,
  ContentPublication,
  ContentPublicationHistoryItem,
  SaveDraftInput,
} from "../../../packages/contracts/src/cloud/wire.ts";
import { contentChecksum } from "../../../packages/contracts/src/content/checksum.ts";
import { publishDraft, type PublishDraftDependencies } from "../publish-draft/index.ts";
import {
  rollbackPublication,
  type RollbackPublicationDependencies,
} from "../rollback-publication/index.ts";
import type {
  CommitPublicationInput,
  ContentStudioRepository,
  RollbackSource,
} from "../_shared/studio.ts";

const ORIGIN = "https://jinhoofkepco.github.io";
const OWNER_ID = "00000000-0000-4000-8000-000000000301";
const EDITOR_ID = "00000000-0000-4000-8000-000000000302";
const DRAFT_ID = "60000000-0000-4000-8000-000000000301";
const PUBLICATION_ID = "71000000-0000-4000-8000-000000000301";
const OPERATION_ID = "81000000-0000-4000-8000-000000000301";
const DATABASE_PUBLISHED_AT = "2026-07-22T04:00:05.000Z";

function commitResult(
  effectiveAt = DATABASE_PUBLISHED_AT,
  status: "active" | "pending" = "active",
) {
  return {
    publicationId: PUBLICATION_ID,
    publishedAt: DATABASE_PUBLISHED_AT,
    effectiveAt,
    status,
  };
}

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

function draftPackage(version = "1.1.0"): ContentDraft["package"] {
  const clone = structuredClone(publishedFixture) as Record<string, unknown>;
  delete clone.checksum;
  clone.content_version = version;
  return clone as unknown as ContentDraft["package"];
}

function draftRecord(packageDraft = draftPackage(), revision = 3): ContentDraft {
  return {
    id: DRAFT_ID,
    activityId: packageDraft.activity_id,
    title: packageDraft.localizations["ko-KR"].title,
    revision,
    updatedAt: "2026-07-22T03:59:00.000Z",
    package: packageDraft,
  };
}

function publishedPackage(version = "1.0.0"): ContentPublication["package"] {
  const draft = draftPackage(version);
  return { ...draft, checksum: contentChecksum(draft) };
}

function rollbackSource(): RollbackSource {
  const packageValue = publishedPackage("1.0.0");
  return {
    publicationId: PUBLICATION_ID,
    activityId: packageValue.activity_id,
    contentVersion: packageValue.content_version,
    checksum: packageValue.checksum,
    package: packageValue,
  };
}

function repository(
  overrides: Partial<ContentStudioRepository> = {},
): ContentStudioRepository {
  return {
    hasRole: (_token, role) => Promise.resolve(role === "owner"),
    getDraft: () => Promise.resolve(draftRecord()),
    saveDraft: (_token, input: SaveDraftInput) =>
      Promise.resolve(draftRecord(input.package, input.expectedRevision ?? 1)),
    commitPublication: () => Promise.resolve(commitResult()),
    getRollbackSource: () => Promise.resolve(rollbackSource()),
    listPublicationHistory: () => Promise.resolve([] as ContentPublicationHistoryItem[]),
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

function publishDependencies(
  overrides: Partial<PublishDraftDependencies> = {},
): PublishDraftDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({ id: OWNER_ID, isAnonymous: false, accessToken: "caller-token" }),
    },
    operationId: () => OPERATION_ID,
    repository: repository(),
    requestId: () => "request-publish",
    ...overrides,
  };
}

function rollbackDependencies(
  overrides: Partial<RollbackPublicationDependencies> = {},
): RollbackPublicationDependencies {
  return {
    allowedOrigins: [ORIGIN],
    auth: {
      verifyBearer: () =>
        Promise.resolve({ id: OWNER_ID, isAnonymous: false, accessToken: "caller-token" }),
    },
    operationId: () => OPERATION_ID,
    repository: repository(),
    requestId: () => "request-rollback",
    ...overrides,
  };
}

Deno.test("publish-draft revalidates, checksums, and commits an owner publication", async () => {
  let committed: CommitPublicationInput | undefined;
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 3,
      reason: "현장 난이도 조정",
    }),
    publishDependencies({
      repository: repository({
        commitPublication: (input) => {
          committed = input;
          return Promise.resolve(commitResult());
        },
      }),
    }),
  );
  const payload = await responseJson(response) as Record<string, unknown>;
  const expectedDraft = draftPackage();
  const expectedChecksum = contentChecksum(expectedDraft);

  assertEquals(response.status, 200);
  assertEquals(payload.activityId, "addition_ones");
  assertEquals(payload.contentVersion, "1.1.0");
  assertEquals(payload.publishedAt, DATABASE_PUBLISHED_AT);
  assertEquals(payload.effectiveAt, DATABASE_PUBLISHED_AT);
  assertEquals(payload.status, "active");
  assertEquals((payload.package as Record<string, unknown>).checksum, expectedChecksum);
  assert(!JSON.stringify(payload).includes("request_id"));
  assert(committed !== undefined);
  assertEquals(committed.actorUserId, OWNER_ID);
  assertEquals(committed.draftId, DRAFT_ID);
  assertEquals(committed.expectedRevision, 3);
  assertEquals(committed.checksum, expectedChecksum);
  assertEquals(committed.validationReport.valid, true);
  assertEquals(committed.reason, "현장 난이도 조정");
  assertEquals(committed.requestId, OPERATION_ID);
  assertEquals(committed.rollbackPublicationId, null);
  assertEquals(committed.effectiveAt, null);
});

Deno.test("publish-draft preserves a future schedule and returns database lifecycle metadata", async () => {
  const future = "2026-07-23T04:00:00.000Z";
  let committed: CommitPublicationInput | undefined;
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 3,
      effectiveAt: future,
      reason: "내일 수업 전에 예약",
    }),
    publishDependencies({
      repository: repository({
        commitPublication: (input) => {
          committed = input;
          return Promise.resolve(commitResult(future, "pending"));
        },
      }),
    }),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 200);
  assertEquals(payload.publishedAt, DATABASE_PUBLISHED_AT);
  assertEquals(payload.effectiveAt, future);
  assertEquals(payload.status, "pending");
  assert(committed !== undefined);
  assertEquals(committed.effectiveAt?.toISOString(), future);
});

Deno.test("publish-draft rejects editors before reading or committing", async () => {
  let read = false;
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 3,
      reason: "편집자 배포 시도",
    }),
    publishDependencies({
      auth: {
        verifyBearer: () =>
          Promise.resolve({ id: EDITOR_ID, isAnonymous: false, accessToken: "caller-token" }),
      },
      repository: repository({
        hasRole: () => Promise.resolve(false),
        getDraft: () => {
          read = true;
          return Promise.resolve(draftRecord());
        },
      }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(read, false);
});

Deno.test("publish-draft rejects a semantic-invalid stored draft before commit", async () => {
  let committed = false;
  const invalid = draftPackage();
  invalid.run.combo_thresholds = [2, 2, 7];
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 3,
      reason: "잘못된 초안",
    }),
    publishDependencies({
      repository: repository({
        getDraft: () => Promise.resolve(draftRecord(invalid)),
        commitPublication: () => {
          committed = true;
          return Promise.resolve(commitResult());
        },
      }),
    }),
  );

  assertEquals(response.status, 422);
  assertEquals(
    ((await responseJson(response) as Record<string, unknown>).error as Record<string, unknown>)
      .code,
    "draft_validation_failed",
  );
  assertEquals(committed, false);
});

Deno.test("publish-draft rejects a poisoned validation answer before commit", async () => {
  let committed = false;
  const poisoned = draftPackage();
  const answer = poisoned.validation_samples[0]!.expected_answer;
  if (answer.kind !== "integer") throw new Error("fixture answer must be integer");
  answer.value += 999;
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 3,
      reason: "변조된 정답 샘플",
    }),
    publishDependencies({
      repository: repository({
        getDraft: () => Promise.resolve(draftRecord(poisoned)),
        commitPublication: () => {
          committed = true;
          return Promise.resolve(commitResult());
        },
      }),
    }),
  );

  assertEquals(response.status, 422);
  assertEquals(committed, false);
});

Deno.test("publish-draft maps an atomic stale revision to a safe conflict", async () => {
  const response = await publishDraft(
    post("publish-draft", {
      draftId: DRAFT_ID,
      expectedRevision: 2,
      reason: "오래된 revision",
    }),
    publishDependencies({
      repository: repository({
        commitPublication: () => Promise.reject({ code: "40001", detail: "locked row" }),
      }),
    }),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 409);
  assertEquals((payload.error as Record<string, unknown>).code, "draft_revision_conflict");
  assert(!JSON.stringify(payload).includes("locked row"));
});

Deno.test("publish-draft requires a nonblank human reason", async () => {
  const response = await publishDraft(
    post("publish-draft", { draftId: DRAFT_ID, expectedRevision: 3, reason: "   " }),
    publishDependencies(),
  );
  assertEquals(response.status, 400);
});

Deno.test("rollback-publication independently validates and reactivates a retired package", async () => {
  let committed: CommitPublicationInput | undefined;
  const source = rollbackSource();
  const response = await rollbackPublication(
    post("rollback-publication", {
      publicationId: PUBLICATION_ID,
      reason: "현장 오류로 안정 버전 복원",
    }),
    rollbackDependencies({
      repository: repository({
        getDraft: () => Promise.resolve(draftRecord(draftPackage("2.0.0"), 8)),
        getRollbackSource: () => Promise.resolve(source),
        commitPublication: (input) => {
          committed = input;
          return Promise.resolve({
            ...commitResult(),
            publicationId: "71000000-0000-4000-8000-000000000399",
            publishedAt: "2026-07-22T04:00:06.000Z",
            effectiveAt: "2026-07-22T04:00:06.000Z",
          });
        },
      }),
    }),
  );
  const payload = await responseJson(response) as Record<string, unknown>;

  assertEquals(response.status, 200);
  assertEquals(payload.activityId, "addition_ones");
  assertEquals(payload.contentVersion, "1.0.0");
  assertEquals(payload.package, source.package);
  assertEquals(payload.publishedAt, "2026-07-22T04:00:06.000Z");
  assertEquals(payload.effectiveAt, "2026-07-22T04:00:06.000Z");
  assertEquals(payload.status, "active");
  assert(committed !== undefined);
  assertEquals(committed.expectedRevision, 8);
  assertEquals(committed.rollbackPublicationId, PUBLICATION_ID);
  assertEquals(committed.checksum, source.checksum);
  assertEquals(committed.reason, "현장 오류로 안정 버전 복원");
  assertEquals(committed.effectiveAt, null);
});

Deno.test("rollback-publication rejects editors before reading history", async () => {
  let read = false;
  const response = await rollbackPublication(
    post("rollback-publication", { publicationId: PUBLICATION_ID, reason: "편집자 복원" }),
    rollbackDependencies({
      repository: repository({
        hasRole: () => Promise.resolve(false),
        getRollbackSource: () => {
          read = true;
          return Promise.resolve(rollbackSource());
        },
      }),
    }),
  );

  assertEquals(response.status, 403);
  assertEquals(read, false);
});

Deno.test("rollback-publication refuses a checksum-invalid historical package", async () => {
  let committed = false;
  const source = rollbackSource();
  source.package.run.starting_hearts = 99;
  const response = await rollbackPublication(
    post("rollback-publication", {
      publicationId: PUBLICATION_ID,
      reason: "변조 이력 복원 시도",
    }),
    rollbackDependencies({
      repository: repository({
        getRollbackSource: () => Promise.resolve(source),
        commitPublication: () => {
          committed = true;
          return Promise.resolve(commitResult());
        },
      }),
    }),
  );

  assertEquals(response.status, 422);
  assertEquals(
    ((await responseJson(response) as Record<string, unknown>).error as Record<string, unknown>)
      .code,
    "historical_validation_failed",
  );
  assertEquals(committed, false);
});
