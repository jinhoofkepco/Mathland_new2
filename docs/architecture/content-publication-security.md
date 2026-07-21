# Content publication security boundary

Draft editing and publication are deliberately separate trust domains.

## Browser and device permissions

- An authenticated `editor` or `owner` may select drafts and may insert only
  `activity_id`, `title`, and `package`. Draft updates are limited to `title`
  and `package`. Authenticated users cannot delete drafts; otherwise deleting
  and recreating an activity would reset its protected revision to one.
- `revision`, creator/updater identity, timestamps, and validation evidence are
  server-owned. The draft trigger derives author metadata from `auth.uid()`,
  advances each authored update by exactly one revision, and clears stale
  validation evidence.
- No authenticated browser role, including `owner`, has direct privileges on
  `content_versions` or `content_publications`.
- A signed-in anonymous device calls `get_active_content_packages()`. The RPC
  returns only the package and checksum behind each currently effective active
  pointer. It does not expose drafts, pending schedules, retired packages,
  publication actors, or version history. The base tables are not selectable by
  devices, guardians, editors, or owners.

## Trusted validation and commit flow

The publication Edge Function is the validation boundary. Its service-role key
is stored only as a deployed function secret and is never returned to the web
application. For every publish or rollback request it must:

1. Authenticate the human request with the caller's user token and require the
   `owner` role. The service role is used only after that authorization succeeds.
2. Load the selected draft and require the caller's expected revision.
3. Parse the original JSON text with the shared strict parser, then run the
   shared TypeScript schema, semantic, generator, and representative-sample
   validators.
4. Construct the published package, canonicalize it with
   `@mathland/contracts`, and compute its canonical SHA-256 checksum.
5. Call `commit_validated_content_publication_v2(...)` once with the locked draft
   revision, published package, checksum, complete successful validation report,
   actor UUID, effective time, request UUID, a human-entered reason of 1–500
   characters, and optional rollback publication.

For a normal publication, the new numeric semantic version must be strictly
greater than every immutable version already stored for the activity. Equal or
lower versions are reserved for the rollback path, which reuses an existing
version row.

The service-role-only function rechecks transaction identities and supplied
evidence, locks the draft, stores the immutable version, changes the publication
pointer, and appends the normalized reason and successful-validation status to
the audit fact in one PostgreSQL transaction. Reasons containing only POSIX
whitespace (including spaces, newlines, tabs, and carriage returns) are rejected.
A stale draft, package/draft mismatch, unsuccessful report, invalid checksum
shape, invalid reason, scheduling conflict, or any database error rolls the
whole statement back.

Each activity has at most one pending schedule. A newly committed normal
publication, replacement schedule, or explicit rollback cancels the previous
pending row and records a `content_publication_cancelled` audit fact before
installing its own pointer. The same activity advisory lock serializes commit,
rollback, and activation, so a due worker cannot race a newer immediate publish
and later downgrade it.

The browser never reads `content_versions` or `content_publications` directly,
including for an owner. An authenticated global content owner calls
`get_content_publication_history(activity_id)`, whose fixed projection returns
only lifecycle timestamps, actor, version, checksum, rollback identity,
validation status, and the human reason. Editors, guardians, devices, and family
membership owners are rejected by that trusted boundary.

Rollback supplies the historical `rollback_publication_id` and its exact stored
package/checksum identity to the same commit RPC. The transaction requires that
the source is a retired publication for the same activity and version. It then
retires the current active pointer and creates a new active publication pointing
to the existing immutable `content_versions` row. It never inserts a duplicate
version. Package substitution, a cross-activity source, or a version mismatch
fails before the pointer or audit log changes.

PostgreSQL intentionally does **not** claim to reproduce JavaScript parsing,
Unicode handling, JSON canonicalization, generator execution, or sample
validation. Reimplementing only part of that behavior in SQL would create a
second validator with misleading guarantees. Database checks protect the atomic
commit and identity relationships; the deployed TypeScript Edge Function owns
content validity and checksum computation.

## Scheduled activation worker

Inserting a `pending` publication does not make PostgreSQL run work when
`effective_at` arrives. Time passing alone has no automatic activation guarantee,
and devices continue to receive the prior active package.

The deployed `activate-publications` Edge Function is the scheduler boundary. It
accepts only a dedicated `MATHLAND_SCHEDULER_SECRET` bearer value, reads at most
1–100 due IDs through `get_due_content_publication_ids(batch_limit)`, and calls
`activate_due_content_publication(publication_id, request_id)` with a fresh
operation UUID for each ID. It creates its service-role repository without the
browser publishable key, CORS allowlist, human authentication, or pairing
secrets. The scheduler secret and service-role credential remain server-only.

The activation RPC takes an activity advisory lock and publication row lock,
rejects early activation, and compares the pending version with the current
active version. It cancels and audits a stale equal/lower schedule instead of
replacing a newer active publication. Otherwise it retires the prior active
pointer, changes the pending row to active, and appends its audit fact in one
transaction. Concurrent or repeated calls return the already-active or
already-cancelled publication without applying the transition or audit twice.
Worker failures are retried with a new request UUID; the publication ID remains
the idempotency identity. Deployment and recovery steps are in
`docs/operations/scheduled-content-activation.md`.

Scheduled activation and rollback must use these service-role boundaries.
Deployment automation must verify that only `service_role` can execute
`commit_validated_content_publication_v2(...)` and
`activate_due_content_publication(...)`. `get_active_content_packages()` is
executable only by `authenticated`, which also covers signed-in anonymous
devices; `service_role` has no execute grant on that device-facing RPC.
