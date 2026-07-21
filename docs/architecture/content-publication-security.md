# Content publication security boundary

Draft editing and publication are deliberately separate trust domains.

## Browser and device permissions

- An authenticated `editor` or `owner` may select drafts and may insert only
  `activity_id`, `title`, and `package`. Draft updates are limited to `title`
  and `package`.
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
5. Call `commit_validated_content_publication(...)` once with the locked draft
   revision, published package, checksum, complete successful validation report,
   actor UUID, effective time, request UUID, and optional rollback publication.

The service-role-only function rechecks transaction identities and supplied
evidence, locks the draft, stores the immutable version, changes the publication
pointer, and appends the audit fact in one PostgreSQL transaction. A stale draft,
package/draft mismatch, unsuccessful report, invalid checksum shape, scheduling
conflict, or any database error rolls the whole statement back.

PostgreSQL intentionally does **not** claim to reproduce JavaScript parsing,
Unicode handling, JSON canonicalization, generator execution, or sample
validation. Reimplementing only part of that behavior in SQL would create a
second validator with misleading guarantees. Database checks protect the atomic
commit and identity relationships; the deployed TypeScript Edge Function owns
content validity and checksum computation.

Scheduled activation and rollback must use the same Edge validation and
service-role commit boundary. Deployment automation must verify that only
`service_role` can execute `commit_validated_content_publication(...)`, while
only `authenticated` and `service_role` can execute
`get_active_content_packages()`.
