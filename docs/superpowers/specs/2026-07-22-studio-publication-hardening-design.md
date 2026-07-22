# Studio Publication Hardening Design

## Scope

This change closes four release-blocking gaps in the Content Studio publication
boundary:

1. Family membership roles must never grant global Studio authority.
2. Immediate publish and rollback timestamps must be owned by PostgreSQL.
3. Draft validation must execute the same generators used at runtime and verify
   every fixed sample independently.
4. Future publications need a deployable, authenticated activation worker.

The shared CORS implementation is intentionally out of scope because the
pairing/ingestion hardening work owns that file. Pairing handlers and migration
`202607220003` are also out of scope.

## Authorization boundary

Add `public.has_global_studio_role(text)`, an authenticated RPC that accepts only
`editor` and `owner` and reads only the signed JWT `app_metadata.role` claim. It
does not inspect `family_memberships`. Keep `has_role(text)` for compatibility,
but remove it from every Studio-sensitive final-state policy and handler.

The following callers use the new predicate:

- Edge `requireStudioRole` through `SupabaseFunctionRepository`;
- content draft select/insert/update RLS;
- global audit-log visibility;
- publication history;
- family membership owner-management clauses that mean global content owner;
- Web session classification and Studio route selection.

Web session classification checks global owner/editor claims first. With no
global Studio role, a family `owner` is treated as a guardian and a family
`editor` receives no Studio role. SQL and Web tests explicitly cover both
negative cases.

## Database-authoritative publication time

Add a service-role-only `commit_validated_content_publication_v2(...)` wrapper
around the existing atomic commit RPC. The wrapper captures one PostgreSQL
`statement_timestamp()`, resolves a null or already-past requested effective time
to that timestamp, preserves a genuinely future time, and forces rollback to the
database timestamp. It returns the committed publication ID, `published_at`,
`effective_at`, and status from the immutable publication row.

The Edge repository sends null for immediate publish and rollback, calls the v2
RPC, and validates its exact one-row result. Publish and rollback responses use
the returned database timestamps and status. The strict `ContentPublication`
wire gains required `effectiveAt` and `status` fields so the browser can
distinguish an active publication from a pending schedule.

SQL tests pass an intentionally stale timestamp to reproduce request latency,
assert equality between immediate `published_at` and `effective_at`, and assert
that a future schedule retains its requested time and pending status. Deno tests
return timestamps from a repository fake that differ from the request and require
those authoritative repository values in the response.

## Runtime-equivalent content validation

Promote the independent mathematical answer verifier into the shared contracts
package. `validateActivityDraft` creates each band generator through
`GeneratorRegistry`, calls its exact `validateParameters`, generates seeds
`1`, `7`, `42`, and `20260721`, independently checks the generated answer from
resolved parameters, and compares it with the authored `expected_answer`.

Every successfully generated sample is returned as a complete
`QuestionInstanceV1`, including layout and manipulative state. Stable validation
issues identify invalid parameter sets, generation failures, independent answer
failures, and poisoned authored sample answers. Since publish and rollback
already call the shared validator, no second Edge-only validation path is added.

Adversarial tests require `operand_min > operand_max` and a modified expected
answer to fail, while all eleven checked-in packages must return twelve generated
samples and no issues.

## Scheduled activation worker

Add `activate-publications`, a server-to-server Edge Function with JWT gateway
verification disabled and its own `MATHLAND_SCHEDULER_SECRET` Bearer check. The
secret must contain at least 32 characters and is compared through fixed-length
SHA-256 digests. Browser origins and user JWTs do not authorize this endpoint.

The JSON request is `{ "batchLimit": 1..100 }`, defaulting to 25. After
authentication, the worker calls the existing service-only bounded due queue and
activates each returned publication through
`activate_due_content_publication(publication_id, request_id)`. The existing SQL
advisory lock and lifecycle checks remain the concurrency and idempotency
boundary. A retry sees no longer-pending rows, while concurrent workers may call
the same ID safely without duplicating transition audit facts.

The response reports processed IDs and count to the trusted scheduler. Any RPC
failure returns a generic retryable diagnostic and leaves already committed
per-publication transitions intact for the next bounded retry.

`supabase/config.toml`, Deno check tasks, handler tests, and an operations runbook
form the deployment contract. The runbook defines secret installation,
function deployment, a five-minute-or-faster external POST schedule, retry and
monitoring behavior, and a manual invocation example without embedding a real
credential.

## Error handling and testing

- Authorization failures are stable 401/403 responses without upstream bodies.
- Invalid scheduler payloads are non-retryable 400 responses.
- Database conflicts retain the existing safe conflict mappings.
- Repository response shape failures become generic 503 responses.
- No service-role table access or browser-facing publication table access is
  introduced.
- TDD cycles cover contracts, handlers, repository wire mapping, and pgTAP.
- Final verification runs contracts tests/typecheck, Deno check/tests, Web tests,
  config tests, and pgTAP/concurrency tests when the local Supabase runtime is
  available.

## Alternatives rejected

- Redefining `has_role(text)` globally is smaller but silently changes family
  semantics and preserves an ambiguous name at a security boundary.
- Adding clock tolerance in Edge still trusts two clocks and cannot return the
  committed database timestamp.
- Validating generators only in `publish-draft` lets Studio previews, AI patches,
  and other contract consumers disagree.
- Calling activation with a human owner JWT makes unattended scheduling depend on
  a user session; database-only cron would not satisfy the externally scheduled
  Edge deployment contract.
