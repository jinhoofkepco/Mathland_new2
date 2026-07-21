# Service-role database boundaries

The Supabase service credential bypasses RLS, so it has no direct privilege on
any table or view in the `public` schema. In particular it cannot read or mutate
drafts, immutable versions, publication pointers, pairing records, learning
events, or the audit log. An Edge Function must call one of the exact
`SECURITY DEFINER` RPCs below; restoring `ALL`, table-level DML, or ad-hoc column
grants to `service_role` is prohibited.

| Boundary | RPCs | Purpose |
| --- | --- | --- |
| Content validation | `get_content_draft_for_validation` | Read one draft's ID, activity, revision, and package without raw table access. |
| Publish/rollback | `get_content_publication_for_rollback`, `commit_validated_content_publication` | Read one retired immutable source and atomically commit a validated publish or rollback with a required 1–500 character human reason. |
| Scheduled worker | `get_due_content_publication_ids`, `activate_due_content_publication` | Read a bounded due queue and atomically activate one pending pointer. |
| Pairing | `create_pairing_challenge_for_service`, `get_pairing_challenge_for_service`, `commit_device_pairing_for_service` | Create a guardian-authorized digest-only challenge, resolve its minimal active metadata, and atomically consume it into one device binding. |
| Event ingestion | `ingest_learning_events_for_service` | Validate a batch of at most 100 `LearningEventV1` objects, derive family/profile identity from the bound device, and acknowledge exact retries idempotently. |

All nine RPCs have an empty `search_path`; only `service_role` receives execute
permission. The content draft reader is intentionally read-only. Publication
versions, active pointers, and audit facts can be written only inside the atomic
commit/activation RPCs. Pairing and ingestion derive protected columns inside
the database rather than accepting family/profile/internal-device IDs from an
Edge Function.

Normal publication versions are parsed component-by-component after a bounded
canonical SemVer regex. Components use PostgreSQL `numeric`, so comparison is
numeric and overflow-safe: `1.10.0` is newer than `1.9.0`. A normal publication
must be greater than every historical version for that activity. Equal or lower
versions are rejected; only the rollback branch may point a new publication at
an older, already immutable version.

Publication and rollback audit facts retain the normalized human reason and
successful validation state. Authenticated browsers still cannot select the raw
version or publication tables. A global content owner may call the separate
`get_content_publication_history(activity_id)` trusted projection; this is an
authenticated owner boundary and is deliberately not one of the nine
service-role RPCs.

## Device reward privacy

`authenticated` has no base-table `SELECT` on `guardian_rewards`. A paired
anonymous device calls `get_device_guardian_rewards()`, which returns only reward
ID, title, apple cost, status, and timestamps for its bound profile. It never
returns `created_by`, family/profile identity, or another child's rows. Guardians
use `get_guardian_rewards(family_id)`, which applies guardian authorization and
also omits the creator auth UUID.

The C5 Edge Functions must pass the authenticated human/device identity into
these fixed boundaries, keep the service credential in deployment secrets, and
must not introduce raw-table fallbacks. Database tests audit the complete
service-role function allowlist and assert that it has zero public table/view
privileges.
