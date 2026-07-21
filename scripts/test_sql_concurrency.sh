#!/usr/bin/env bash
set -euo pipefail

MATHLAND_DATABASE_URL="${MATHLAND_DATABASE_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
MATHLAND_PSQL_BIN="${MATHLAND_PSQL_BIN:-psql}"
MATHLAND_CONCURRENCY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mathland-sql-concurrency.XXXXXX")"

cleanup_concurrency_logs() {
  rm -f \
    "$MATHLAND_CONCURRENCY_TMP/pairing-a.log" \
    "$MATHLAND_CONCURRENCY_TMP/pairing-b.log" \
    "$MATHLAND_CONCURRENCY_TMP/publication.log" \
    "$MATHLAND_CONCURRENCY_TMP/activation.log"
  rmdir "$MATHLAND_CONCURRENCY_TMP"
}
trap cleanup_concurrency_logs EXIT

sql_value() {
  "$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" \
    -X -v ON_ERROR_STOP=1 -Atq -c "$1"
}

wait_for_advisory_owner() {
  local advisory_key="$1"
  local attempt
  local lock_available
  for ((attempt = 1; attempt <= 100; attempt++)); do
    lock_available="$(sql_value "select pg_catalog.pg_try_advisory_lock(${advisory_key})")"
    if [[ "$lock_available" == "f" ]]; then
      return 0
    fi
    sleep 0.02
  done
  echo "FAIL: timed out waiting for concurrent session advisory marker ${advisory_key}." >&2
  return 1
}

MATHLAND_GUARDIAN_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_FAMILY_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_PROFILE_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_PAIRING_DIGEST_A="$(sql_value "select pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')")"
MATHLAND_PAIRING_DIGEST_B="$(sql_value "select pg_catalog.encode(extensions.gen_random_bytes(32), 'hex')")"

"$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -v guardian_id="$MATHLAND_GUARDIAN_ID" \
  -v family_id="$MATHLAND_FAMILY_ID" \
  -v profile_id="$MATHLAND_PROFILE_ID" <<'SQL' >/dev/null
insert into auth.users (id) values (:'guardian_id');
insert into public.families (id, name, created_by)
values (:'family_id', 'Concurrent pairing family', :'guardian_id');
insert into public.family_memberships (family_id, user_id, role)
values (:'family_id', :'guardian_id', 'guardian');
insert into public.child_profiles (
  id, family_id, client_profile_id, nickname, created_by
) values (
  :'profile_id', :'family_id', 'concurrent-profile', 'Concurrent child',
  :'guardian_id'
);

create function public.mathland_test_pairing_insert_pause()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform pg_catalog.pg_sleep(0.5);
  return new;
end;
$$;

create trigger mathland_test_pairing_insert_pause
before insert on public.pairing_codes
for each row execute function public.mathland_test_pairing_insert_pause();
SQL

pairing_worker() {
  local pairing_digest_hex="$1"
  "$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
    -v profile_id="$MATHLAND_PROFILE_ID" \
    -v guardian_id="$MATHLAND_GUARDIAN_ID" \
    -v pairing_digest_hex="$pairing_digest_hex" <<'SQL'
begin;
set local role service_role;
select public.create_pairing_challenge_for_service(
  :'profile_id',
  pg_catalog.decode(:'pairing_digest_hex', 'hex'),
  pg_catalog.statement_timestamp() + interval '10 minutes',
  :'guardian_id'
);
commit;
SQL
}

pairing_worker "$MATHLAND_PAIRING_DIGEST_A" \
  >"$MATHLAND_CONCURRENCY_TMP/pairing-a.log" 2>&1 &
MATHLAND_PAIRING_PID_A=$!
pairing_worker "$MATHLAND_PAIRING_DIGEST_B" \
  >"$MATHLAND_CONCURRENCY_TMP/pairing-b.log" 2>&1 &
MATHLAND_PAIRING_PID_B=$!

set +e
wait "$MATHLAND_PAIRING_PID_A"
MATHLAND_PAIRING_STATUS_A=$?
wait "$MATHLAND_PAIRING_PID_B"
MATHLAND_PAIRING_STATUS_B=$?
set -e

if [[ "$MATHLAND_PAIRING_STATUS_A" -ne 0 || "$MATHLAND_PAIRING_STATUS_B" -ne 0 ]]; then
  sed -n '1,120p' "$MATHLAND_CONCURRENCY_TMP/pairing-a.log"
  sed -n '1,120p' "$MATHLAND_CONCURRENCY_TMP/pairing-b.log"
  echo "FAIL: both concurrent pairing creations must commit successfully." >&2
  exit 1
fi

MATHLAND_ACTIVE_PAIRINGS="$(sql_value "select count(*) from public.pairing_codes where profile_id = '$MATHLAND_PROFILE_ID' and consumed_at is null and invalidated_at is null")"
MATHLAND_PAIRING_AUDITS="$(sql_value "select count(*) from public.audit_log where action = 'pairing_challenge_created' and target_id = '$MATHLAND_PROFILE_ID'")"
if [[ "$MATHLAND_ACTIVE_PAIRINGS" != "1" || "$MATHLAND_PAIRING_AUDITS" != "2" ]]; then
  echo "FAIL: concurrent pairing invariant active=$MATHLAND_ACTIVE_PAIRINGS audits=$MATHLAND_PAIRING_AUDITS." >&2
  exit 1
fi

"$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
drop trigger mathland_test_pairing_insert_pause on public.pairing_codes;
drop function public.mathland_test_pairing_insert_pause();
SQL

MATHLAND_OWNER_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_DRAFT_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_VERSION_ONE_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_VERSION_TWO_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_ACTIVE_ONE_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_PENDING_TWO_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_PUBLISH_REQUEST_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_ACTIVATION_REQUEST_ID="$(sql_value 'select extensions.gen_random_uuid()')"
MATHLAND_ACTIVITY_ID="concurrency_$(printf '%s' "$MATHLAND_DRAFT_ID" | tr -d '-')"
MATHLAND_CHECKSUM_ONE="sha256:$(sql_value "select encode(extensions.digest('${MATHLAND_ACTIVITY_ID}:1', 'sha256'), 'hex')")"
MATHLAND_CHECKSUM_TWO="sha256:$(sql_value "select encode(extensions.digest('${MATHLAND_ACTIVITY_ID}:2', 'sha256'), 'hex')")"
MATHLAND_CHECKSUM_THREE="sha256:$(sql_value "select encode(extensions.digest('${MATHLAND_ACTIVITY_ID}:3', 'sha256'), 'hex')")"
MATHLAND_PUBLICATION_READY_KEY="$(sql_value "select pg_catalog.hashtextextended('${MATHLAND_ACTIVITY_ID}:publication-ready', 0)")"
MATHLAND_ACTIVATION_READY_KEY="$(sql_value "select pg_catalog.hashtextextended('${MATHLAND_ACTIVITY_ID}:activation-ready', 0)")"

"$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -v owner_id="$MATHLAND_OWNER_ID" \
  -v draft_id="$MATHLAND_DRAFT_ID" \
  -v version_one_id="$MATHLAND_VERSION_ONE_ID" \
  -v version_two_id="$MATHLAND_VERSION_TWO_ID" \
  -v active_one_id="$MATHLAND_ACTIVE_ONE_ID" \
  -v pending_two_id="$MATHLAND_PENDING_TWO_ID" \
  -v activity_id="$MATHLAND_ACTIVITY_ID" \
  -v checksum_one="$MATHLAND_CHECKSUM_ONE" \
  -v checksum_two="$MATHLAND_CHECKSUM_TWO" <<'SQL' >/dev/null
insert into auth.users (id, app_metadata) values (:'owner_id', '{"role":"owner"}');
insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values (
  :'draft_id', :'activity_id', 'Concurrent publication',
  pg_catalog.jsonb_build_object(
    'activity_id', :'activity_id',
    'content_version', '3.0.0'
  ),
  :'owner_id', :'owner_id'
);
insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    :'version_one_id', :'activity_id', '1.0.0', :'checksum_one',
    pg_catalog.jsonb_build_object(
      'activity_id', :'activity_id',
      'content_version', '1.0.0',
      'checksum', :'checksum_one'
    ),
    1, :'owner_id'
  ),
  (
    :'version_two_id', :'activity_id', '2.0.0', :'checksum_two',
    pg_catalog.jsonb_build_object(
      'activity_id', :'activity_id',
      'content_version', '2.0.0',
      'checksum', :'checksum_two'
    ),
    1, :'owner_id'
  );
insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status
) values
  (
    :'active_one_id', :'activity_id', '1.0.0', :'version_one_id', :'owner_id',
    pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp(), 'active'
  ),
  (
    :'pending_two_id', :'activity_id', '2.0.0', :'version_two_id', :'owner_id',
    pg_catalog.statement_timestamp(),
    pg_catalog.statement_timestamp() + interval '1 second',
    'pending'
  );
SQL

sleep 1.1

"$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -v draft_id="$MATHLAND_DRAFT_ID" \
  -v owner_id="$MATHLAND_OWNER_ID" \
  -v activity_id="$MATHLAND_ACTIVITY_ID" \
  -v checksum_three="$MATHLAND_CHECKSUM_THREE" \
  -v request_id="$MATHLAND_PUBLISH_REQUEST_ID" \
  -v ready_lock_key="$MATHLAND_PUBLICATION_READY_KEY" \
  >"$MATHLAND_CONCURRENCY_TMP/publication.log" 2>&1 <<'SQL' &
begin;
set local role service_role;
select public.commit_validated_content_publication(
  :'draft_id',
  1,
  pg_catalog.jsonb_build_object(
    'activity_id', :'activity_id',
    'content_version', '3.0.0',
    'checksum', :'checksum_three'
  ),
  :'checksum_three',
  '{"valid":true,"issues":[],"samples":[]}'::jsonb,
  :'owner_id',
  pg_catalog.statement_timestamp(),
  :'request_id',
  'Concurrent newer publication',
  null
);
select pg_catalog.pg_advisory_lock(:'ready_lock_key'::bigint);
select pg_catalog.pg_sleep(2);
select pg_catalog.pg_advisory_unlock(:'ready_lock_key'::bigint);
commit;
SQL
MATHLAND_PUBLICATION_PID=$!

wait_for_advisory_owner "$MATHLAND_PUBLICATION_READY_KEY"

"$MATHLAND_PSQL_BIN" "$MATHLAND_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -v pending_two_id="$MATHLAND_PENDING_TWO_ID" \
  -v request_id="$MATHLAND_ACTIVATION_REQUEST_ID" \
  -v ready_lock_key="$MATHLAND_ACTIVATION_READY_KEY" \
  >"$MATHLAND_CONCURRENCY_TMP/activation.log" 2>&1 <<'SQL' &
begin;
set local role service_role;
select pg_catalog.pg_advisory_lock(:'ready_lock_key'::bigint);
select public.activate_due_content_publication(:'pending_two_id', :'request_id');
select pg_catalog.pg_advisory_unlock(:'ready_lock_key'::bigint);
commit;
SQL
MATHLAND_ACTIVATION_PID=$!

wait_for_advisory_owner "$MATHLAND_ACTIVATION_READY_KEY"

set +e
wait "$MATHLAND_PUBLICATION_PID"
MATHLAND_PUBLICATION_STATUS=$?
wait "$MATHLAND_ACTIVATION_PID"
MATHLAND_ACTIVATION_STATUS=$?
set -e

if [[ "$MATHLAND_PUBLICATION_STATUS" -ne 0 || "$MATHLAND_ACTIVATION_STATUS" -ne 0 ]]; then
  sed -n '1,160p' "$MATHLAND_CONCURRENCY_TMP/publication.log"
  sed -n '1,160p' "$MATHLAND_CONCURRENCY_TMP/activation.log"
  echo "FAIL: publication/activation race workers must both commit." >&2
  exit 1
fi

MATHLAND_ACTIVE_VERSION="$(sql_value "select content_version from public.content_publications where activity_id = '$MATHLAND_ACTIVITY_ID' and status = 'active'")"
MATHLAND_PENDING_STATUS="$(sql_value "select status from public.content_publications where id = '$MATHLAND_PENDING_TWO_ID'")"
MATHLAND_CANCELLATION_AUDITS="$(sql_value "select count(*) from public.audit_log where action = 'content_publication_cancelled' and target_id = '$MATHLAND_PENDING_TWO_ID'")"
if [[ "$MATHLAND_ACTIVE_VERSION" != "3.0.0" || "$MATHLAND_PENDING_STATUS" != "cancelled" || "$MATHLAND_CANCELLATION_AUDITS" != "1" ]]; then
  echo "FAIL: publication race active=$MATHLAND_ACTIVE_VERSION pending=$MATHLAND_PENDING_STATUS cancellations=$MATHLAND_CANCELLATION_AUDITS." >&2
  exit 1
fi

echo "PASS: concurrent pairing leaves one active challenge and two audited creations."
echo "PASS: a newer normal publication cancels a racing stale schedule without downgrade."
