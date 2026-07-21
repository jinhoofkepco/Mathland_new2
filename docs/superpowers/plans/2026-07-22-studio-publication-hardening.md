# Studio Publication Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close global Studio authorization, publication timestamp, generator validation, and scheduled activation release blockers without touching the pairing/CORS hardening scope.

**Architecture:** A new global-only SQL claim predicate becomes the single Studio authorization primitive across Web, Edge, RLS, and history. A service-only publication wrapper owns immediate timestamps and returns exact commit metadata, the shared content validator executes the runtime generator registry and independent answer verifier, and a secret-authenticated bounded Edge worker drives the existing idempotent activation RPCs.

**Tech Stack:** PostgreSQL 17/RLS/pgTAP, Supabase Edge Functions on Deno, TypeScript/Zod, React Supabase JS, Vitest.

## Global Constraints

- Do not modify `supabase/functions/_shared/http.ts`, pairing handlers/tests, or migration `202607220003`.
- Use migration `202607220004_studio_publication_hardening.sql` and pgTAP test `015_studio_publication_hardening.sql`.
- Family membership `owner`/`editor` never grants a global Studio role.
- Immediate time is PostgreSQL-owned; genuinely future schedules preserve the requested instant.
- Validation executes all three bands at seeds `1`, `7`, `42`, and `20260721` and independently verifies answers.
- The scheduler endpoint is server-to-server only and requires a secret of at least 32 characters.
- Never expose service-role credentials, scheduler secrets, SQL bodies, or stack traces.

---

### Task 1: Global-only Studio authorization

**Files:**
- Create: `supabase/migrations/202607220004_studio_publication_hardening.sql`
- Create: `supabase/tests/015_studio_publication_hardening.sql`
- Modify: `supabase/functions/_shared/supabase.ts`
- Modify: `web/src/cloud/supabase_cloud.ts`
- Test: `supabase/functions/tests/content_studio.test.ts`
- Test: `web/src/cloud/supabase_cloud.test.ts`

**Interfaces:**
- Consumes: JWT `app_metadata.role`, existing `ContentStudioRepository.hasRole`.
- Produces: `public.has_global_studio_role(required_role text) returns boolean`; Edge `hasRole` calls that RPC.

- [ ] **Step 1: Write failing SQL and Web role-separation tests**

Add pgTAP identities with family membership roles but empty app metadata and assert:

```sql
select is(public.has_global_studio_role('owner'), false,
  'family owner is not a global Studio owner');
select is((select count(*) from public.content_drafts), 0::bigint,
  'family owner cannot read global drafts');
select throws_like(
  $$select * from public.get_content_publication_history(null)$$,
  '%owner role is required%',
  'family owner cannot read global publication history'
);
```

Add Web tests whose membership row is `owner` or `editor` while both global-role RPCs return false. Expect family owner to become `guardian`, and family editor to become `unauthorized`. Add a Deno repository/handler assertion that the requested RPC name is `has_global_studio_role`.

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
npm run test:web -- --run src/cloud/supabase_cloud.test.ts
npx deno test --sloppy-imports --allow-env supabase/functions/tests/content_studio.test.ts
```

Expected: Web family-owner/editor assertions fail because membership roles are selected first; the Deno RPC-name assertion fails because `has_role` is called. pgTAP remains pending until the migration exists.

- [ ] **Step 3: Implement the explicit global predicate and update consumers**

Migration 004 defines and grants only:

```sql
create function public.has_global_studio_role(required_role text)
returns boolean language sql stable security definer set search_path = '' as $$
  select required_role in ('editor', 'owner')
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = required_role;
$$;
revoke all on function public.has_global_studio_role(text) from public, anon, service_role;
grant execute on function public.has_global_studio_role(text) to authenticated;
```

Drop/recreate final membership-owner, content-draft, and global-audit policies with `has_global_studio_role`, and recreate history with the same predicate. Change Edge repository RPC selection. Change Web session logic to check global owner/editor first, then map family `guardian` or `owner` to guardian and never map family editor to Studio.

- [ ] **Step 4: Run targeted tests to verify GREEN**

Run the two commands from Step 2. Expected: both pass.

- [ ] **Step 5: Commit authorization changes**

```bash
git add supabase/migrations/202607220004_studio_publication_hardening.sql \
  supabase/tests/015_studio_publication_hardening.sql \
  supabase/functions/_shared/supabase.ts supabase/functions/tests/content_studio.test.ts \
  web/src/cloud/supabase_cloud.ts web/src/cloud/supabase_cloud.test.ts
git commit -m "fix(studio): separate global roles from family membership"
```

### Task 2: Runtime-equivalent generator and sample validation

**Files:**
- Create: `packages/contracts/src/content/generation/independent_verify.ts`
- Modify: `packages/contracts/src/content/index.ts`
- Modify: `packages/contracts/src/content/validate.ts`
- Modify: `tools/content/independent_verify.ts`
- Modify: `packages/contracts/test/content/package_fixture.ts`
- Test: `packages/contracts/test/content/validate.test.ts`
- Test: `packages/contracts/test/content/migrated_packages.test.ts`
- Test: `packages/contracts/test/content/foundations_packages.test.ts`
- Test: `supabase/functions/tests/content_studio.test.ts`
- Test: `supabase/functions/tests/publication.test.ts`

**Interfaces:**
- Consumes: `GeneratorRegistry`, `QuestionGeneratorContract.validateParameters/generate`, authored validation samples.
- Produces: `verifyGeneratedAnswer(...)`; `validateActivityDraft` returns twelve `QuestionInstanceV1` samples for a valid package.

- [ ] **Step 1: Write adversarial failing contract tests**

Use a checked-in valid addition draft and assert:

```ts
const invalidRange = structuredClone(valid);
invalidRange.difficulty_bands[0]!.generator_parameters.operand_min = 10;
invalidRange.difficulty_bands[0]!.generator_parameters.operand_max = 1;
expect(issueCodes(validateActivityDraft(invalidRange))).toContain("GENERATOR_PARAMETERS_INVALID");

const poisoned = structuredClone(valid);
poisoned.validation_samples[0]!.expected_answer.value += 999;
expect(issueCodes(validateActivityDraft(poisoned))).toContain("VALIDATION_SAMPLE_ANSWER_MISMATCH");
expect(validateActivityDraft(valid).samples).toHaveLength(12);
```

Change the Deno validation test to expect twelve complete samples and add a publish test proving poisoned stored content returns 422 before commit.

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
npx vitest run --config packages/contracts/vitest.config.ts packages/contracts/test/content/validate.test.ts
npx deno test --sloppy-imports --allow-env supabase/functions/tests/content_studio.test.ts supabase/functions/tests/publication.test.ts
```

Expected: invalid parameter and poisoned-answer tests report valid; sample-count assertions receive zero.

- [ ] **Step 3: Promote independent verification and execute generators in the validator**

Move the dependency-free verifier into contracts and re-export it. For each parsed band, validate exact generator parameters, generate all four fixed seeds, call `verifyGeneratedAnswer`, compare the generated and authored answer structurally, and append:

```ts
{
  contract_version: 1,
  activity_id: draft.activity_id,
  content_version: draft.content_version,
  generator_id: band.generator_id,
  band_id: band.band_id,
  seed,
  resolved_parameters: generated.resolved_parameters,
  prompt: generated.prompt,
  correct_answer: generated.correct_answer,
  answer_layout: structuredClone(band.answer_layout),
  manipulative: structuredClone(band.manipulative),
}
```

Use stable issue codes and exact band/sample paths. Replace the synthetic test helper with clones of checked-in valid source packages so every baseline fixture satisfies generator contracts.

- [ ] **Step 4: Run targeted and complete contract tests to verify GREEN**

```bash
npx vitest run --config packages/contracts/vitest.config.ts packages/contracts/test/content/validate.test.ts
npm run test:contracts -- --run
npx deno test --sloppy-imports --allow-env supabase/functions/tests/content_studio.test.ts supabase/functions/tests/publication.test.ts
```

Expected: all pass; eleven package tests each receive twelve valid samples.

- [ ] **Step 5: Commit validation changes**

```bash
git add packages/contracts/src/content packages/contracts/test/content \
  tools/content/independent_verify.ts supabase/functions/tests/content_studio.test.ts \
  supabase/functions/tests/publication.test.ts
git commit -m "fix(content): validate runtime generators before publish"
```

### Task 3: PostgreSQL-owned publication timestamps and strict response wire

**Files:**
- Modify: `supabase/migrations/202607220004_studio_publication_hardening.sql`
- Modify: `supabase/tests/015_studio_publication_hardening.sql`
- Modify: `supabase/tests/008_service_boundaries.sql`
- Modify: `packages/contracts/src/cloud/wire.ts`
- Modify: `packages/contracts/test/cloud/wire.test.ts`
- Modify: `supabase/functions/_shared/studio.ts`
- Modify: `supabase/functions/_shared/supabase.ts`
- Modify: `supabase/functions/publish-draft/index.ts`
- Modify: `supabase/functions/rollback-publication/index.ts`
- Test: `supabase/functions/tests/publication.test.ts`
- Modify: `web/src/cloud/fake_cloud.ts`
- Test: `web/src/cloud/supabase_cloud.test.ts`

**Interfaces:**
- Consumes: existing `commit_validated_content_publication` transaction.
- Produces: service RPC `commit_validated_content_publication_v2`; `CommitPublicationResult`; strict response fields `effectiveAt` and `status`.

- [ ] **Step 1: Write failing wire and handler tests**

Require `ContentPublicationSchema` to parse only when both authoritative fields are present. Make repository fakes return:

```ts
{
  publicationId: PUBLICATION_ID,
  publishedAt: "2026-07-22T04:00:05.000Z",
  effectiveAt: "2026-07-22T04:00:05.000Z",
  status: "active",
}
```

Assert publish/rollback responses use these timestamps rather than handler time. Add SQL tests that pass `statement_timestamp() - interval '5 minutes'` and require returned `effective_at = published_at`, plus a future call requiring pending status and an unchanged future instant.

- [ ] **Step 2: Run tests to verify RED**

```bash
npx vitest run --config packages/contracts/vitest.config.ts packages/contracts/test/cloud/wire.test.ts
npx deno test --sloppy-imports --allow-env supabase/functions/tests/publication.test.ts
```

Expected: wire rejects/omits the new fields and handlers return the local clock.

- [ ] **Step 3: Implement v2 wrapper and authoritative result mapping**

Define the wrapper with a database timestamp and exact result:

```sql
resolved_effective_at := case
  when rollback_publication_id is not null then server_timestamp
  when target_effective_at is null or target_effective_at <= server_timestamp then server_timestamp
  else target_effective_at
end;
committed_id := public.commit_validated_content_publication(..., resolved_effective_at, ...);
return query select id, published_at, effective_at, status
  from public.content_publications where id = committed_id;
```

Grant only service role. Update repository parsing to require a one-row result. Make immediate Edge calls pass null and response parsing use the result. Extend strict contracts and FakeCloud.

- [ ] **Step 4: Run targeted tests to verify GREEN**

Run the Step 2 commands plus `npm run test:web -- --run src/cloud/supabase_cloud.test.ts`. Expected: all pass.

- [ ] **Step 5: Commit timestamp changes**

```bash
git add supabase/migrations/202607220004_studio_publication_hardening.sql \
  supabase/tests/015_studio_publication_hardening.sql packages/contracts/src/cloud/wire.ts \
  packages/contracts/test/cloud/wire.test.ts supabase/functions/_shared/studio.ts \
  supabase/functions/_shared/supabase.ts supabase/functions/publish-draft/index.ts \
  supabase/functions/rollback-publication/index.ts supabase/functions/tests/publication.test.ts \
  web/src/cloud/fake_cloud.ts web/src/cloud/supabase_cloud.test.ts
git commit -m "fix(studio): use database publication timestamps"
```

### Task 4: Trusted scheduled activation Edge worker

**Files:**
- Create: `supabase/functions/_shared/scheduler.ts`
- Create: `supabase/functions/activate-publications/index.ts`
- Create: `supabase/functions/tests/activation_worker.test.ts`
- Modify: `supabase/functions/_shared/supabase.ts`
- Modify: `supabase/config.toml`
- Modify: `deno.json`
- Create: `docs/operations/scheduled-content-activation.md`
- Modify: `docs/architecture/content-publication-security.md`
- Modify: `docs/architecture/service-role-boundaries.md`

**Interfaces:**
- Consumes: `get_due_content_publication_ids(limit)` and `activate_due_content_publication(id, request_id)`.
- Produces: `PublicationActivationRepository`; POST `/functions/v1/activate-publications` request `{batchLimit?: number}` and response `{processed: number, publicationIds: string[]}`.

- [ ] **Step 1: Write failing worker authentication and lifecycle tests**

Cover missing/wrong Bearer as 401 without repository access, invalid limits as 400, valid bounded processing, empty retry as a successful zero result, concurrent handler invocations returning safely through an idempotent repository fake, and generic 503 without upstream detail.

- [ ] **Step 2: Run tests to verify RED**

```bash
npx deno test --sloppy-imports --allow-env supabase/functions/tests/activation_worker.test.ts
```

Expected: module import fails because worker files do not exist.

- [ ] **Step 3: Implement secret verifier, repository methods, and handler**

Verify `Authorization: Bearer` by SHA-256 digest comparison, authenticate before JSON parsing, default batch limit to 25, sequentially activate returned UUIDs with fresh operation IDs, and return exact JSON through `wireResponse`. Add a scheduler-only runtime factory that requires only `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `MATHLAND_SCHEDULER_SECRET`.

- [ ] **Step 4: Add deployment contract and runbook**

Configure:

```toml
[functions.activate-publications]
verify_jwt = false
```

Add the handler to `check:functions`. Document `supabase secrets set`, deploy with no gateway JWT verification, a redacted curl POST, cadence no slower than five minutes, retry semantics, audit/history monitoring, and secret rotation.

- [ ] **Step 5: Run worker and complete Deno tests**

```bash
npx deno task check:functions
npx deno task test:functions
./scripts/test_supabase_config.sh
```

Expected: check passes and all Deno/config tests pass.

- [ ] **Step 6: Commit worker changes**

```bash
git add supabase/functions/_shared/scheduler.ts supabase/functions/activate-publications \
  supabase/functions/tests/activation_worker.test.ts supabase/functions/_shared/supabase.ts \
  supabase/config.toml deno.json docs/operations/scheduled-content-activation.md \
  docs/architecture/content-publication-security.md docs/architecture/service-role-boundaries.md
git commit -m "feat(studio): add trusted publication activation worker"
```

### Task 5: Full verification and integration handoff

**Files:**
- Verify only; modify a test or implementation file only if a failing command exposes a scoped defect.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: clean branch commits and exact verification evidence for root cherry-pick.

- [ ] **Step 1: Run formatting and static checks**

```bash
npx deno fmt --check supabase/functions deno.json
npm run typecheck
git diff --check 67584b2..HEAD
```

Expected: all pass with no formatting or whitespace errors.

- [ ] **Step 2: Run complete automated suites**

```bash
npm run test:contracts -- --run
npm run test:web -- --run
npx deno task check:functions
npx deno task test:functions
./scripts/test_supabase_config.sh
```

Expected: all pass.

- [ ] **Step 3: Run PostgreSQL tests when available**

```bash
./scripts/test_sql.sh
```

Expected: all pgTAP and concurrency tests pass. If Supabase CLI/Docker is unavailable, report that exact environmental blocker and retain static SQL evidence.

- [ ] **Step 4: Inspect scope and commits**

```bash
git status --short
git log --oneline 67584b2..HEAD
git diff --stat 67584b2..HEAD
git show --check --oneline HEAD
```

Expected: clean worktree, only scoped files, coherent commit history.
