# Cloud, Dashboard, and Content Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the secure Supabase contracts, guardian dashboard, and owner-only Content Studio that accept duplicate-safe child events, expose only authorized family aggregates, and publish validated content versions without putting privileged credentials in the static client.

**Architecture:** A React/Vite static application uses the publishable Supabase client and RLS for reads, while privileged mutations go through small Edge Functions. PostgreSQL owns identity bindings, immutable events, aggregate views, publication pointers, and audit history. All browser flows run against deterministic fakes before the credential gate; the same typed contracts are exercised against a live Supabase project only during final integration.

**Tech Stack:** TypeScript 5, React 19, Vite 7, React Router, TanStack Query, Supabase JS, Zod, Vitest, React Testing Library, MSW, Playwright, PostgreSQL, pgTAP, Supabase Edge Functions on Deno.

## Global Constraints

- Treat `docs/superpowers/specs/2026-07-21-mathland-godot-redesign-design.md` as the source of truth.
- Import wire contracts from `packages/contracts`; do not redefine `LearningEventV1` or content schemas in the web app or functions.
- Keep the service-role key and AI provider keys exclusively in Edge Function secrets. Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` may enter the browser bundle.
- Every family-scoped table must enable RLS and have negative cross-family tests before a route consumes it.
- An AI response is a draft patch only. It must never write a publication pointer or child learning data.
- Keep the dashboard usable against deterministic fakes until a real Supabase project is authorized.
- Run the named failing test before each production change and retain the observed failure in the task notes.
- Commit only after the complete task test command passes.

## File Structure

- `packages/contracts/`: B-owned canonical Zod/type definitions consumed unchanged by the web app and Edge Functions.
- `web/src/config/`: strict public runtime configuration and secret rejection.
- `web/src/cloud/`: the `CloudPort`, production Supabase adapter, deterministic fake, and React provider.
- `web/src/auth/`: magic-link session lifecycle and route/role guards.
- `web/src/dashboard/`: pure query state plus guardian metrics and sync visibility.
- `web/src/devices/`, `web/src/rewards/`, `web/src/data/`: explicit guardian mutations and destructive-action confirmations.
- `web/src/studio/`: manual/JSON editing, deterministic previews, validation, publication history, rollback, and optional AI patch review.
- `web/e2e/`: fake-backed guardian/editor browser journeys at phone and tablet widths.
- `supabase/migrations/`: ordered schema, helper, view, RLS, and function definitions.
- `supabase/tests/`: pgTAP constraints, RLS-negative cases, idempotency, export, and deletion.
- `supabase/functions/_shared/`: authenticated HTTP, repository, contract, and optional AI provider boundaries.
- `supabase/functions/<operation>/`: one independently testable privileged operation per directory.
- `docs/cloud/`: local development, deployment, security, content, privacy, recovery, and rotation runbooks.

---

### Task 1: Establish the TypeScript workspace and web test harness

**Files:**

- Modify: `package.json`
- Modify: `package-lock.json` through `npm install`
- Create: `web/package.json`
- Create: `web/index.html`
- Create: `web/tsconfig.json`
- Create: `web/vite.config.ts`
- Create: `web/vitest.config.ts`
- Create: `web/playwright.config.ts`
- Create: `web/src/main.tsx`
- Create: `web/src/app/App.tsx`
- Create: `web/src/styles/tokens.css`
- Create: `web/src/styles/global.css`
- Create: `web/src/test/setup.ts`
- Test: `web/src/app/App.test.tsx`

**Interfaces:**

- Consumes: the root npm workspace and `@mathland/contracts` created by Subproject B, plus the approved `/Mathland_new2/` deployment path.
- Produces: npm workspace scripts `test:web`, `test:e2e`, `typecheck`, `build:web`; exported React component `App(): JSX.Element`.

- [ ] **Step 1: Write the app-shell test**

```tsx
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { App } from "./App";

it("renders the signed-out MathLand shell in Korean", () => {
  render(<MemoryRouter><App /></MemoryRouter>);
  expect(screen.getByRole("heading", { name: "MathLand 보호자" })).toBeVisible();
  expect(screen.getByRole("link", { name: "이메일로 시작하기" })).toHaveAttribute("href", "/login");
});
```

- [ ] **Step 2: Run the focused test and verify the red state**

Run: `npm --workspace web test -- --run src/app/App.test.tsx`

Expected: FAIL because the `web` workspace and `App` module do not exist.

- [ ] **Step 3: Extend the npm workspace and install exact dependency classes**

Preserve B's package/workspace scripts while adding `web` plus root scripts `test:web`, `test:e2e`, `typecheck`, and `build:web`. The web workspace must include React, React DOM, React Router, TanStack Query, Supabase JS, Zod, Vite, TypeScript, Vitest, jsdom, Testing Library, MSW, and Playwright. Commit the generated lockfile.

- [ ] **Step 4: Implement the minimal routed shell and design tokens**

Use `/Mathland_new2/` as Vite's production base, Korean as the document language, a visible skip link, and the approved mint/sky/sand/coral/apple/gold palette as CSS custom properties. The root route renders the tested heading and login link.

- [ ] **Step 5: Run tests, type checking, and production build**

Run: `npm --workspace web test -- --run src/app/App.test.tsx && npm --workspace web run typecheck && npm --workspace web run build`

Expected: one passing test, no TypeScript errors, and `web/dist/index.html` containing `/Mathland_new2/assets/` URLs.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json web
git commit -m "build(web): scaffold dashboard workspace"
```

### Task 2: Add environment validation and a replaceable cloud port

**Files:**

- Create: `web/.env.example`
- Create: `web/src/config/runtime_env.ts`
- Create: `web/src/cloud/cloud_port.ts`
- Create: `web/src/cloud/supabase_client.ts`
- Create: `web/src/cloud/supabase_cloud.ts`
- Create: `web/src/cloud/fake_cloud.ts`
- Create: `web/src/cloud/cloud_provider.tsx`
- Test: `web/src/config/runtime_env.test.ts`
- Test: `web/src/cloud/fake_cloud.test.ts`

**Interfaces:**

- Consumes: `@mathland/contracts` domain and wire types.
- Produces: `parseRuntimeEnv(record): RuntimeEnv`, `CloudPort`, `SupabaseCloud`, `FakeCloud`, and `useCloud(): CloudPort`.

- [ ] **Step 1: Write configuration and fake-cloud tests**

The environment test must accept valid `https://project.supabase.co` plus an `sb_publishable_` key, reject a missing URL, and reject a `service_role` key. The fake-cloud test must return only children in the requested fake family and must preserve event aggregate ordering.

- [ ] **Step 2: Verify the tests fail for missing modules**

Run: `npm --workspace web test -- --run src/config/runtime_env.test.ts src/cloud/fake_cloud.test.ts`

Expected: FAIL with unresolved module errors.

- [ ] **Step 3: Define the cloud interface**

```ts
export interface CloudPort {
  session(): Promise<SessionState>;
  sendMagicLink(email: string, redirectTo: string): Promise<void>;
  signOut(): Promise<void>;
  listFamilies(): Promise<FamilySummary[]>;
  listChildren(familyId: string): Promise<ChildSummary[]>;
  dashboard(query: DashboardQuery): Promise<DashboardSnapshot>;
  createPairingCode(profileId: string): Promise<PairingCodeResult>;
  disconnectDevice(deviceId: string): Promise<void>;
  exportFamily(familyId: string): Promise<Blob>;
  deleteProfile(profileId: string, confirmation: string): Promise<void>;
  listDrafts(): Promise<ContentDraftSummary[]>;
  loadDraft(draftId: string): Promise<ContentDraft>;
  saveDraft(input: SaveDraftInput): Promise<ContentDraft>;
  validateDraft(draftId: string): Promise<ValidationReport>;
  publishDraft(draftId: string, expectedRevision: number): Promise<ContentPublication>;
  rollbackPublication(activityId: string, contentVersion: string): Promise<ContentPublication>;
  requestAiPatch(draftId: string, instruction: string): Promise<AiPatchResult>;
}
```

All IDs and response bodies come from `@mathland/contracts`. `FakeCloud` uses immutable fixtures and asynchronous methods so components cannot depend on synchronous fake behavior.

- [ ] **Step 4: Implement strict environment parsing and the Supabase adapter**

Create the Supabase browser client with `persistSession: true`, `autoRefreshToken: true`, and PKCE. Invoke Edge Functions for pairing/admin mutations; query only authorized views for dashboard reads. Never fall back to a secret or embed a sample project URL.

- [ ] **Step 5: Run the focused tests**

Run: `npm --workspace web test -- --run src/config/runtime_env.test.ts src/cloud/fake_cloud.test.ts`

Expected: all configuration and isolation cases pass.

- [ ] **Step 6: Commit**

```bash
git add web/.env.example web/src/config web/src/cloud
git commit -m "feat(web): define replaceable cloud boundary"
```

### Task 3: Create the database schema, constraints, and immutable audit primitives

**Files:**

- Create: `supabase/config.toml`
- Create: `supabase/migrations/202607210001_extensions_and_identity.sql`
- Create: `supabase/migrations/202607210002_learning_and_rewards.sql`
- Create: `supabase/migrations/202607210003_content_and_audit.sql`
- Create: `supabase/migrations/202607210004_views_and_helpers.sql`
- Create: `supabase/tests/001_schema_constraints.sql`
- Create: `scripts/test_sql.sh`

**Interfaces:**

- Consumes: `LearningEventV1` and `ActivityPackageV1` JSON field names from `@mathland/contracts`.
- Produces: the thirteen approved tables, guardian aggregate views, and SQL helpers `is_family_member(uuid)`, `is_family_guardian(uuid)`, and `has_role(text)`.

- [ ] **Step 1: Write pgTAP constraints before migrations**

Cover all thirteen approved tables, UUID primary keys, unique `(device_id, local_sequence)`, globally unique `learning_events.event_id`, nonnegative durations/rewards, pairing-code digest storage rather than plaintext, immutable content-version uniqueness, one active publication per activity, and append-only audit/event protections.

- [ ] **Step 2: Run the SQL suite and verify the red state**

Run when Supabase CLI is available: `./scripts/test_sql.sh`

Expected: FAIL because the relations and helper functions do not exist. If the CLI is unavailable, run `npx supabase --version`; installation/download failure is recorded as an environment gate, not converted into a skipped test.

- [ ] **Step 3: Implement identity and membership tables**

Create `families`, `family_memberships`, `child_profiles`, `devices`, and `pairing_codes`. Use `auth.users(id)` foreign keys; store profile nicknames but no exact birth date; include `deleted_at`; store pairing `code_digest`, `expires_at`, `consumed_at`, and attempt count. Use `security definer` helper functions with an explicit empty `search_path` for `is_family_member`, `is_family_guardian`, and `has_role`.

- [ ] **Step 4: Implement events, snapshots, and rewards**

Store the canonical LearningEventV1 payload as validated `jsonb` plus indexed columns for family/profile/device/type/activity/time. Add `progress_snapshots`, `reward_inventory`, and `guardian_rewards`. Reject update/delete on learning events except through the profile-deletion function.

- [ ] **Step 5: Implement content and audit tables**

Add `content_drafts` with optimistic `revision`, immutable `content_versions` with checksum/package, `content_publications` with publication time and actor, and append-only `audit_log`. AI audit entries contain only administrator instruction, selected draft revision, resulting patch, provider identifier, and status; they never contain child logs.

- [ ] **Step 6: Implement aggregate views**

Create `guardian_session_summary`, `guardian_activity_summary`, `guardian_error_patterns`, and `guardian_reward_summary`. Each row includes `family_id` so RLS-authorized wrapper functions can filter before returning data. Define stale sync from the latest device `last_sync_at`, not browser time.

- [ ] **Step 7: Run SQL tests**

Run: `./scripts/test_sql.sh`

Expected: all schema/constraint pgTAP assertions pass from a clean local database.

- [ ] **Step 8: Commit**

```bash
git add supabase scripts/test_sql.sh
git commit -m "feat(cloud): add secure MathLand data schema"
```

### Task 4: Enforce all RLS role boundaries

**Files:**

- Create: `supabase/migrations/202607210005_rls.sql`
- Create: `supabase/tests/002_rls_guardian.sql`
- Create: `supabase/tests/003_rls_device.sql`
- Create: `supabase/tests/004_rls_content_roles.sql`
- Create: `supabase/tests/005_deletion.sql`

**Interfaces:**

- Consumes: Task 3 tables and helper functions.
- Produces: forced RLS policies, `export_family_data(uuid)`, and `delete_child_profile(uuid, text)` callable by authenticated guardians.

- [ ] **Step 1: Write negative policy tests first**

Create two families, a guardian, an editor, an owner, and two device users. Assert denial of every cross-family select/insert/update/delete; denial of device reads of guardian identity; denial of direct event insert with the wrong profile; denial of editor publication; and denial of guardian draft access. Assert profile deletion removes all cloud child rows while retaining an anonymized audit fact.

- [ ] **Step 2: Run and observe policy failures**

Run: `./scripts/test_sql.sh`

Expected: FAIL because RLS has not been enabled and unauthorized reads succeed.

- [ ] **Step 3: Enable RLS and add least-privilege policies**

Enable and force RLS on every public table. Guardians manage only active memberships and profiles in their families. Devices insert through the ingest function only and may read only their own device binding/public content. Editors manage drafts and validation records. Owners publish, roll back, and configure AI metadata. Revoke default public function execution before granting exact roles.

- [ ] **Step 4: Add deletion and export functions**

Implement `export_family_data(family_id)` and `delete_child_profile(profile_id, confirmation_nickname)` as authenticated functions that re-check membership inside the transaction. Deletion must consume pairing codes, disconnect devices, remove event/snapshot/reward rows, and mark the profile deleted.

- [ ] **Step 5: Run the full SQL suite**

Run: `./scripts/test_sql.sh`

Expected: all positive cases work and every cross-family/role-negative assertion passes.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/202607210005_rls.sql supabase/tests
git commit -m "security(cloud): enforce family and role isolation"
```

### Task 5: Implement the pairing and idempotent ingestion Edge Functions

**Files:**

- Create: `supabase/functions/_shared/auth.ts`
- Create: `supabase/functions/_shared/http.ts`
- Create: `supabase/functions/_shared/contracts.ts`
- Create: `supabase/functions/_shared/supabase.ts`
- Create: `supabase/functions/create-pairing-code/index.ts`
- Create: `supabase/functions/pair-device/index.ts`
- Create: `supabase/functions/ingest-events/index.ts`
- Create: `supabase/functions/tests/pairing.test.ts`
- Create: `supabase/functions/tests/ingestion.test.ts`
- Create: `deno.json`

**Interfaces:**

- Consumes: device/profile bindings from Task 3, RLS rules from Task 4, and `LearningEventV1Schema` from `@mathland/contracts`.
- Produces: HTTP handlers `createPairingCode(request)`, `pairDevice(request)`, and `ingestEvents(request)` plus the stable `IngestResponse` envelope.

- [ ] **Step 1: Write Edge Function contract tests**

Test missing/expired/used/wrong pairing codes, one-profile binding, digest comparison, rate limiting, malformed batches, more than 100 events, out-of-sequence device IDs, duplicate event IDs, mixed accepted/already-present results, and schema/permission/auth error codes. Inject repositories and clocks so tests require no live project.

- [ ] **Step 2: Run tests and verify red**

Run: `deno test --allow-env supabase/functions/tests/pairing.test.ts supabase/functions/tests/ingestion.test.ts`

Expected: FAIL with missing handler modules.

- [ ] **Step 3: Implement shared request/auth helpers**

Return JSON envelopes with stable diagnostic codes, explicit CORS allowlists, request IDs, and no stack traces. Verify bearer tokens with the project Auth endpoint and pass the caller JWT to RLS-sensitive reads. Construct service-role clients only inside the function runtime.

- [ ] **Step 4: Implement pairing handlers**

`create-pairing-code` requires an active guardian, generates a cryptographically random six-character numeric code, stores only an HMAC digest, expires it after ten minutes, and invalidates prior unused codes for that profile. `pair-device` requires an anonymous Auth user, atomically consumes the code, creates/updates one device binding, and returns non-sensitive family/profile identifiers.

- [ ] **Step 5: Implement ingestion**

Validate every event with the shared Zod contract, require 1–100 ordered items, compare device/profile binding, insert with `on conflict (event_id) do nothing`, update `last_sync_at`, and return:

```ts
type IngestResponse = {
  accepted_event_ids: string[];
  already_present_event_ids: string[];
  server_cursor: string;
};
```

The whole valid batch is transactional. Contract/permission errors reject the entire batch and expose a non-retryable diagnostic code.

- [ ] **Step 6: Run formatter, type check, and tests**

Run: `deno fmt --check supabase/functions && deno check supabase/functions/create-pairing-code/index.ts supabase/functions/pair-device/index.ts supabase/functions/ingest-events/index.ts && deno test --allow-env supabase/functions/tests`

Expected: all contract tests pass with no formatter/type errors.

- [ ] **Step 7: Commit**

```bash
git add deno.json supabase/functions
git commit -m "feat(cloud): add secure pairing and event ingestion"
```

### Task 6: Build magic-link authentication and guarded routing

**Files:**

- Create: `web/src/auth/auth_provider.tsx`
- Create: `web/src/auth/require_session.tsx`
- Create: `web/src/auth/require_role.tsx`
- Create: `web/src/auth/LoginPage.tsx`
- Create: `web/src/auth/AuthCallbackPage.tsx`
- Create: `web/src/layout/AppLayout.tsx`
- Modify: `web/src/app/App.tsx`
- Test: `web/src/auth/LoginPage.test.tsx`
- Test: `web/src/auth/require_role.test.tsx`

**Interfaces:**

- Consumes: `CloudPort.session`, `sendMagicLink`, and `signOut` from Task 2.
- Produces: `AuthProvider`, `useAuth`, `RequireSession`, and `RequireRole({ allow })` used by all authenticated routes.

- [ ] **Step 1: Write auth route tests**

Assert email validation, disabled submit during request, Korean success/error text, preservation of intended route, guardian denial of `/studio`, editor access to drafts but not publish controls, owner access to publish, and sign-out returning to `/login`.

- [ ] **Step 2: Run tests and verify red**

Run: `npm --workspace web test -- --run src/auth`

Expected: FAIL because auth components do not exist.

- [ ] **Step 3: Implement accessible auth pages and providers**

Use labels, `aria-live` status, focus transfer on errors, PKCE callback handling, and an allowlisted same-origin redirect. Session role comes from a server/RLS-backed membership query, never editable browser storage.

- [ ] **Step 4: Add guarded route tree**

Routes: `/login`, `/auth/callback`, `/dashboard`, `/dashboard/:familyId/:profileId`, `/devices`, `/data`, `/studio`, `/studio/drafts/:draftId`, and `/studio/history`. Unauthenticated routes redirect to login; wrong-role routes render a 403 page without initiating privileged requests.

- [ ] **Step 5: Run auth tests and build**

Run: `npm --workspace web test -- --run src/auth && npm --workspace web run typecheck && npm --workspace web run build`

Expected: all auth tests pass and no service-role token literal exists in `web/dist`.

- [ ] **Step 6: Commit**

```bash
git add web/src/auth web/src/layout web/src/app/App.tsx
git commit -m "feat(web): add magic-link auth and role gates"
```

### Task 7: Implement dashboard query state and learning aggregates

**Files:**

- Create: `web/src/dashboard/dashboard_types.ts`
- Create: `web/src/dashboard/dashboard_query.ts`
- Create: `web/src/dashboard/dashboard_reducer.ts`
- Create: `web/src/dashboard/formatters.ts`
- Create: `web/src/dashboard/DashboardPage.tsx`
- Create: `web/src/dashboard/RangeTabs.tsx`
- Create: `web/src/dashboard/ChildPicker.tsx`
- Create: `web/src/dashboard/SummaryCards.tsx`
- Create: `web/src/dashboard/ActivityProgressTable.tsx`
- Create: `web/src/dashboard/ErrorPatterns.tsx`
- Create: `web/src/dashboard/RecentSessions.tsx`
- Create: `web/src/dashboard/RewardSummary.tsx`
- Create: `web/src/dashboard/SyncStatus.tsx`
- Test: `web/src/dashboard/dashboard_reducer.test.ts`
- Test: `web/src/dashboard/DashboardPage.test.tsx`

**Interfaces:**

- Consumes: `CloudPort.listFamilies`, `listChildren`, and `dashboard`; authorized aggregate records from Task 3.
- Produces: `DashboardPage`, `dashboardReducer(state, action)`, and URL-backed `DashboardQuery` with `range: "today" | "7d" | "30d"`.

- [ ] **Step 1: Write reducer and page tests**

Cover today/7/30 date windows in `Asia/Seoul`, family versus child selection, zero-attempt accuracy, time formatting, repeated-error ordering, adaptive-change labels, health-depletion runs, combo records, reward counts, loading/empty/error states, and stale device state. Use a fixed clock and Korean locale.

- [ ] **Step 2: Run and verify red**

Run: `npm --workspace web test -- --run src/dashboard`

Expected: FAIL with unresolved dashboard modules.

- [ ] **Step 3: Implement pure query/reducer logic**

The URL owns `range` and selected profile so refresh/back work. Reduce server results without recomputing security-sensitive family membership. Stale status thresholds are explicit: current under 15 minutes, delayed under 24 hours, offline at or above 24 hours.

- [ ] **Step 4: Implement responsive dashboard components**

At 360 px, render one-column cards and horizontally scrollable labeled tables; at tablet/desktop, use a two-column grid. Charts require accompanying numeric text/table. Accuracy uses icon/text in addition to color. Never show a real-name field.

- [ ] **Step 5: Connect TanStack Query through CloudPort**

Use query keys containing family, profile, and range. Keep prior visible data during range changes, show `last_sync_at`, retry only transient reads twice, and do not silently retry 401/403.

- [ ] **Step 6: Run dashboard tests**

Run: `npm --workspace web test -- --run src/dashboard && npm --workspace web run typecheck`

Expected: reducer and rendered fake-cloud scenarios pass.

- [ ] **Step 7: Commit**

```bash
git add web/src/dashboard
git commit -m "feat(web): add guardian learning dashboard"
```

### Task 8: Add device pairing, rewards, export, and deletion controls

**Files:**

- Create: `web/src/devices/DevicesPage.tsx`
- Create: `web/src/devices/PairingCodeDialog.tsx`
- Create: `web/src/rewards/GuardianRewards.tsx`
- Create: `web/src/data/DataControlsPage.tsx`
- Create: `web/src/data/DeleteProfileDialog.tsx`
- Test: `web/src/devices/DevicesPage.test.tsx`
- Test: `web/src/data/DataControlsPage.test.tsx`

**Interfaces:**

- Consumes: the six guardian mutation methods on `CloudPort` and Task 4 export/deletion authorization.
- Produces: routed `DevicesPage`, `DataControlsPage`, `GuardianRewards`, and reusable confirmation dialogs.

- [ ] **Step 1: Write mutation safety tests**

Assert pairing expiry display, one-time-code masking after dialog close, device disconnect confirmation, reward validation, export filename, typed nickname deletion confirmation, failure preserving UI state, and successful deletion removing the child from cached queries.

- [ ] **Step 2: Verify red**

Run: `npm --workspace web test -- --run src/devices src/data`

Expected: FAIL because pages are missing.

- [ ] **Step 3: Implement guarded mutation flows**

Do not persist pairing codes in local/session storage. Require explicit confirmation for disconnect and deletion. Use server-provided export blobs and revoke object URLs after download. Guardian rewards have a title, child-visible description, apple cost, active flag, and no cash-equivalent behavior.

- [ ] **Step 4: Run tests**

Run: `npm --workspace web test -- --run src/devices src/data src/rewards && npm --workspace web run typecheck`

Expected: all mutation and safety scenarios pass.

- [ ] **Step 5: Commit**

```bash
git add web/src/devices web/src/rewards web/src/data
git commit -m "feat(web): add family devices rewards and data controls"
```

### Task 9: Implement content draft storage, deterministic validation, and preview

**Files:**

- Create: `supabase/functions/validate-content/index.ts`
- Create: `supabase/functions/tests/validate_content.test.ts`
- Create: `web/src/studio/StudioPage.tsx`
- Create: `web/src/studio/DraftEditorPage.tsx`
- Create: `web/src/studio/ActivityForm.tsx`
- Create: `web/src/studio/JsonEditor.tsx`
- Create: `web/src/studio/SamplePreview.tsx`
- Create: `web/src/studio/ValidationPanel.tsx`
- Create: `web/src/studio/draft_diff.ts`
- Test: `web/src/studio/draft_diff.test.ts`
- Test: `web/src/studio/DraftEditorPage.test.tsx`

**Interfaces:**

- Consumes: `ActivityPackageDraftSchema`, generator registry/sample protocol, and draft methods on `CloudPort`.
- Produces: `validateContent(request)`, `DraftEditorPage`, `diffDraft(before, after)`, and typed `ValidationReport` rendering.

- [ ] **Step 1: Write function and UI tests**

Cover schema errors with JSON paths, unknown generators/manipulatives/resources, checksum exclusion during draft validation, every band sampled with fixed seeds, independent answer verification, optimistic revision conflicts, form/JSON round trips, ten-rod preview, unsaved-change navigation warning, and manual editing with no AI configuration.

- [ ] **Step 2: Run and verify red**

Run: `deno test --allow-env supabase/functions/tests/validate_content.test.ts && npm --workspace web test -- --run src/studio`

Expected: FAIL with missing validation function and Studio modules.

- [ ] **Step 3: Implement server validation**

Invoke the shared package validator and deterministic generator registry for the same seed set used by the Godot fixtures. Return typed field errors plus resolved sample question/answer/manipulative states. Reject packages whose requested scene/resource is outside the checked-in allowlist.

- [ ] **Step 4: Implement the editor and diff**

Provide generator-specific fields, ordered difficulty bands, health/target/timer/reward/combo/effect fields, localized copy, allowlisted scene/icon/manipulative pickers, raw JSON editing, and a structural before/after diff. Saving uses `expected_revision`; a conflict loads both versions and never overwrites silently.

- [ ] **Step 5: Implement accessible previews**

Render numeric/text descriptions alongside visual ten frames, rods, number lines, and counters. Samples show seed, generator ID, band, resolved parameters, submitted/correct form, and validation result.

- [ ] **Step 6: Run validation and Studio tests**

Run: `deno test --allow-env supabase/functions/tests/validate_content.test.ts && npm --workspace web test -- --run src/studio && npm --workspace web run typecheck`

Expected: deterministic validation and all edit/conflict/preview tests pass.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/validate-content web/src/studio supabase/functions/tests/validate_content.test.ts
git commit -m "feat(studio): add validated content editing and preview"
```

### Task 10: Add immutable publication, scheduling, audit history, and rollback

**Files:**

- Create: `supabase/functions/publish-content/index.ts`
- Create: `supabase/functions/rollback-content/index.ts`
- Create: `supabase/functions/tests/publication.test.ts`
- Create: `web/src/studio/PublishDialog.tsx`
- Create: `web/src/studio/HistoryPage.tsx`
- Create: `web/src/studio/RollbackDialog.tsx`
- Test: `web/src/studio/publication.test.tsx`

**Interfaces:**

- Consumes: a successful Task 9 validation report and Task 3 content/audit tables.
- Produces: `publishContent(request)`, `rollbackContent(request)`, immutable `ContentPublication`, and owner-only publication/history UI.

- [ ] **Step 1: Write publication invariants first**

Test editor rejection, owner success, invalid draft rejection, stale revision rejection, semver monotonicity, canonical checksum, immutable package insertion, atomic publication-pointer update, scheduled UTC publication, audit actor/reason, rollback only to a validated historical version, and no mutation of an already published package.

- [ ] **Step 2: Run and verify red**

Run: `deno test --allow-env supabase/functions/tests/publication.test.ts && npm --workspace web test -- --run src/studio/publication.test.tsx`

Expected: FAIL because publication handlers/components do not exist.

- [ ] **Step 3: Implement transactional publish and rollback handlers**

Canonicalize JSON, compute SHA-256 server-side, re-run validation inside the transaction, write an immutable `content_versions` row, update one activity pointer, and append audit data. For scheduling, store a validated pending publication and use a database cron invocation that repeats the same owner/validation checks.

- [ ] **Step 4: Implement owner-only UI**

Show validation summary, version, checksum, effective time, diff, and explicit confirmation. History displays actor, timestamp, reason, version, checksum, and validation status. Rollback creates a new publication event pointing to an old immutable package.

- [ ] **Step 5: Run tests**

Run: `deno test --allow-env supabase/functions/tests/publication.test.ts && npm --workspace web test -- --run src/studio && npm --workspace web run typecheck`

Expected: role, atomicity, immutable history, and rollback cases pass.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/publish-content supabase/functions/rollback-content supabase/functions/tests/publication.test.ts web/src/studio
git commit -m "feat(studio): publish and roll back immutable content"
```

### Task 11: Add the optional AI draft-patch adapter

**Files:**

- Create: `supabase/functions/_shared/ai_provider.ts`
- Create: `supabase/functions/ai-draft-patch/index.ts`
- Create: `supabase/functions/tests/ai_draft_patch.test.ts`
- Create: `web/src/studio/AiDraftPanel.tsx`
- Test: `web/src/studio/AiDraftPanel.test.tsx`

**Interfaces:**

- Consumes: the selected `ActivityPackageDraft`, Task 9 validator, and server-only AI provider environment.
- Produces: `AiDraftProvider.createPatch`, `aiDraftPatch(request)`, and `AiDraftPanel` returning a reviewable unsaved patch only.

- [ ] **Step 1: Write boundary and failure tests**

Cover no provider configured, timeout, malformed JSON, patch paths outside the selected draft, schema-invalid patch, sample-invalid patch, provider text leakage, child-event field rejection, editor request allowed, owner publication still separate, and successful human-readable diff. Assert the provider receives only instruction plus selected draft content.

- [ ] **Step 2: Run and verify red**

Run: `deno test --allow-env supabase/functions/tests/ai_draft_patch.test.ts && npm --workspace web test -- --run src/studio/AiDraftPanel.test.tsx`

Expected: FAIL with missing adapter and panel.

- [ ] **Step 3: Implement a provider-neutral interface**

```ts
export interface AiDraftProvider {
  createPatch(input: {
    instruction: string;
    draft: ActivityPackageDraft;
  }, signal: AbortSignal): Promise<JsonPatchOperation[]>;
}
```

The Edge Function chooses a provider from server environment, enforces a timeout and response-size cap, validates RFC 6902 operations against an allowed path set, applies to an in-memory copy, and runs the same full validation. It returns patch, diff, and validation report without saving or publishing.

- [ ] **Step 4: Implement the optional UI**

When configuration is absent, explain in Korean that manual editing remains fully available. When present, show instruction, pending state, diff, validation, Apply-to-Draft, and Discard. Applying changes only the local unsaved draft and requires the normal save/publish flow.

- [ ] **Step 5: Run tests and scan for child-data coupling**

Run: `deno test --allow-env supabase/functions/tests/ai_draft_patch.test.ts && npm --workspace web test -- --run src/studio/AiDraftPanel.test.tsx && rg -n "learning_events|submitted_answer|correct_answer" supabase/functions/ai-draft-patch web/src/studio/AiDraftPanel.tsx`

Expected: tests pass; the scan finds only explicit rejection assertions/test fixtures, not provider payload construction.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared/ai_provider.ts supabase/functions/ai-draft-patch supabase/functions/tests/ai_draft_patch.test.ts web/src/studio/AiDraftPanel.tsx web/src/studio/AiDraftPanel.test.tsx
git commit -m "feat(studio): add review-only AI draft patches"
```

### Task 12: Add browser journeys and responsive/accessibility gates

**Files:**

- Create: `web/e2e/fixtures/fake_cloud.ts`
- Create: `web/e2e/guardian_dashboard.spec.ts`
- Create: `web/e2e/content_studio.spec.ts`
- Create: `web/e2e/offline_and_errors.spec.ts`
- Create: `web/e2e/accessibility.spec.ts`
- Create: `web/src/test/browser_fake_entry.ts`
- Modify: `web/playwright.config.ts`

**Interfaces:**

- Consumes: all routed UI and `FakeCloud` scenarios.
- Produces: repeatable `npm --workspace web run test:e2e` evidence at 360×800 and 800×1280.

- [ ] **Step 1: Write failing browser journeys**

Cover magic-link callback stub, child/range selection, dashboard metrics, stale/offline indicator, pairing, export, delete confirmation cancellation, manual content edit, validation failure, corrected validation, owner publish, rollback, AI unavailable, and 403 role gates. Run viewports at 360×800 and 800×1280.

- [ ] **Step 2: Run and confirm red**

Run: `npm --workspace web run test:e2e`

Expected: FAIL until the fake-browser entry and stable selectors are wired.

- [ ] **Step 3: Wire deterministic browser fakes and fix surfaced defects**

Select the fake adapter only when `VITE_USE_FAKE_CLOUD=true` at build time. It must never be enabled by missing production configuration. Use role/name locators, visible Korean labels, and test IDs only for non-semantic canvas previews.

- [ ] **Step 4: Add automated accessibility assertions**

Use `@axe-core/playwright`; fail on serious/critical issues, missing labels, keyboard traps, focus loss after dialogs, color-only statuses, or touch targets below 48 CSS pixels at the phone viewport.

- [ ] **Step 5: Run the complete web gate**

Run: `npm --workspace web test -- --run && npm --workspace web run typecheck && npm --workspace web run build && npm --workspace web run test:e2e`

Expected: all unit/component/browser tests pass at both target viewports.

- [ ] **Step 6: Commit**

```bash
git add web/e2e web/src/test/browser_fake_entry.ts web/playwright.config.ts web/package.json package-lock.json
git commit -m "test(web): cover guardian and studio journeys"
```

### Task 13: Add GitHub Pages deployment and operator documentation

**Files:**

- Create: `.github/workflows/web.yml`
- Create: `docs/cloud/local-development.md`
- Create: `docs/cloud/supabase-deployment.md`
- Create: `docs/cloud/security-and-rls.md`
- Create: `docs/cloud/content-operations.md`
- Create: `docs/cloud/privacy-operations.md`
- Create: `scripts/scan_client_secrets.sh`
- Test: `web/src/config/no_secrets.test.ts`

**Interfaces:**

- Consumes: Tasks 1–12 outputs and repository/Pages configuration.
- Produces: deployable `web/dist`, CI gates, `scan_client_secrets.sh`, and complete operator runbooks.

- [ ] **Step 1: Write the client-secret scan test**

Fail on `service_role`, private-key blocks, signing passwords, non-example JWTs, local development URLs, or known personal values in tracked web assets/build output. Allow only the publishable key variable name and `.env.example` placeholders.

- [ ] **Step 2: Verify the scan catches an injected fixture**

Run: `npm --workspace web test -- --run src/config/no_secrets.test.ts`

Expected: the test's intentional secret fixture is detected and the clean repository fixture passes.

- [ ] **Step 3: Add CI and Pages workflow**

On pull requests, run contract tests, web unit/type/build/e2e, Deno checks, and secret scans. On `main`, deploy only `web/dist` to GitHub Pages. Pass publishable configuration via repository variables, never secrets exposed to fork builds; if variables are absent, deploy the clearly labeled local-demo fake build until the live credential gate is completed.

- [ ] **Step 4: Document exact local and live operations**

Include CLI commands for local Supabase start/reset/test/functions serve, creating the first owner membership through an authenticated SQL/admin procedure, configuring magic-link redirect URLs, setting function secrets, applying migrations, deploying functions, rotating keys, validating RLS, publishing/rolling back content, exporting/deleting data, disconnecting devices, and restoring the prior publication. Do not include real project IDs, emails, or secrets.

- [ ] **Step 5: Run all cloud/web checks**

Run: `./scripts/scan_client_secrets.sh && npm --workspace web test -- --run && npm --workspace web run typecheck && npm --workspace web run build && deno fmt --check supabase/functions && deno test --allow-env supabase/functions/tests`

Expected: every available deterministic test passes; SQL tests pass when the local Supabase runtime is installed. The only permitted unresolved item is the explicitly documented live-project authorization gate.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/web.yml docs/cloud scripts/scan_client_secrets.sh web/src/config/no_secrets.test.ts
git commit -m "ci(cloud): deploy and operate dashboard safely"
```

### Task 14: Execute the authorized live-cloud verification gate

**Files:**

- Create after authorization: `docs/verification/live-cloud-report.md`
- Modify after authorization: `web/.env.example` only if a public variable name changes
- Modify after authorization: `.github/workflows/web.yml` only if the deployed Pages origin changes

**Interfaces:**

- Consumes: an authorized Supabase project, the production Godot event client from A/D, and all locally passing C suites.
- Produces: deployed schema/functions/static configuration and `docs/verification/live-cloud-report.md` with non-secret evidence.

- [ ] **Step 1: Pause only for trusted Supabase authorization**

Use browser/CLI device authorization; never request a password, access token, service-role key, or AI key in chat. Confirm the selected project ID and intended Pages origin with read-only commands before mutation.

- [ ] **Step 2: Deploy from a clean verified commit**

Run the exact documented migration, RLS test, function deployment, redirect configuration, and Pages variable setup commands. Capture command versions, migration IDs, and function versions without recording secrets.

- [ ] **Step 3: Execute live isolation and product smoke tests**

Create two temporary test families, verify all cross-family reads/writes fail, pair one disposable device identity, ingest one LearningEventV1 twice, assert one stored event, and verify the guardian aggregate updates. Create/validate/publish/rollback one disposable content version. Delete all disposable records through product deletion flows.

- [ ] **Step 4: Write the evidence report**

Record UTC/KST time, commit SHA, project reference (public identifier only), deployed migration/function versions, test commands and pass counts, duplicate-ingestion evidence, RLS-negative evidence, dashboard observation, content rollback evidence, cleanup, and remaining limitations.

- [ ] **Step 5: Commit the non-secret report**

```bash
git add docs/verification/live-cloud-report.md
git commit -m "docs(cloud): record live security and sync verification"
```

The cloud subproject is complete only after this gate passes. Without authorization, report it as the single outstanding external gate while keeping all local contracts, fakes, schema, functions, and UI runnable.
