-- Draft deletion would let an editor recreate an activity at revision one.
-- Draft lifecycle deletion is therefore server-only.
drop policy if exists content_drafts_delete_staff on public.content_drafts;
revoke delete on public.content_drafts from authenticated;

create or replace function public.commit_validated_content_publication(
  target_draft_id uuid,
  expected_revision integer,
  published_package jsonb,
  canonical_checksum text,
  validation_report jsonb,
  actor_user_id uuid,
  target_effective_at timestamptz,
  publication_request_id uuid,
  rollback_publication_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  draft_record public.content_drafts%rowtype;
  rollback_record record;
  new_version_id uuid;
  new_publication_id uuid := extensions.gen_random_uuid();
  target_content_version text;
  publication_status text;
  audit_action text;
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  select draft.*
  into draft_record
  from public.content_drafts draft
  where draft.id = target_draft_id
  for update;

  if not found then
    raise exception 'content draft does not exist' using errcode = '22023';
  end if;
  if draft_record.revision <> expected_revision then
    raise exception 'content draft revision is stale' using errcode = '40001';
  end if;
  if validation_report is null
    or pg_catalog.jsonb_typeof(validation_report) <> 'object'
    or validation_report -> 'valid' is distinct from 'true'::jsonb
    or pg_catalog.jsonb_typeof(validation_report -> 'issues') <> 'array'
    or pg_catalog.jsonb_array_length(validation_report -> 'issues') <> 0
    or pg_catalog.jsonb_typeof(validation_report -> 'samples') <> 'array' then
    raise exception 'server validation report is not successful' using errcode = '22023';
  end if;
  if canonical_checksum !~ '^sha256:[0-9a-f]{64}$' then
    raise exception 'canonical checksum is invalid' using errcode = '22023';
  end if;
  if pg_catalog.jsonb_typeof(published_package) <> 'object'
    or published_package ->> 'checksum' is distinct from canonical_checksum then
    raise exception 'validated package checksum identity does not match'
      using errcode = '22023';
  end if;
  if actor_user_id is null or publication_request_id is null then
    raise exception 'publication actor and request id are required' using errcode = '22023';
  end if;
  if target_effective_at is null then
    raise exception 'publication effective time is required' using errcode = '22023';
  end if;

  target_content_version := published_package ->> 'content_version';
  if target_content_version is null then
    raise exception 'validated package has no content version' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(draft_record.activity_id, 0)
  );

  if rollback_publication_id is not null then
    select
      publication.activity_id,
      publication.content_version,
      publication.status,
      version.id as version_id,
      version.checksum,
      version.package
    into rollback_record
    from public.content_publications publication
    join public.content_versions version
      on version.id = publication.version_id
     and version.activity_id = publication.activity_id
     and version.content_version = publication.content_version
    where publication.id = rollback_publication_id;

    if not found
      or rollback_record.status <> 'retired'
      or rollback_record.activity_id is distinct from draft_record.activity_id
      or rollback_record.content_version is distinct from target_content_version
      or rollback_record.checksum is distinct from canonical_checksum
      or rollback_record.package is distinct from published_package then
      raise exception 'rollback publication identity does not match the immutable version'
        using errcode = '22023';
    end if;
    if target_effective_at > server_timestamp then
      raise exception 'rollback must reactivate immediately' using errcode = '22023';
    end if;

    new_version_id := rollback_record.version_id;
    publication_status := 'active';
    audit_action := 'content_rolled_back';
  else
    if published_package - 'checksum' is distinct from draft_record.package
      or published_package ->> 'activity_id' is distinct from draft_record.activity_id then
      raise exception 'validated package does not match the locked draft'
        using errcode = '22023';
    end if;

    update public.content_drafts
    set validation_report = commit_validated_content_publication.validation_report,
        validation_checksum = canonical_checksum
    where id = target_draft_id;

    new_version_id := extensions.gen_random_uuid();
    insert into public.content_versions (
      id,
      activity_id,
      content_version,
      checksum,
      package,
      source_draft_id,
      source_revision,
      created_by,
      created_at
    ) values (
      new_version_id,
      draft_record.activity_id,
      target_content_version,
      canonical_checksum,
      published_package,
      draft_record.id,
      draft_record.revision,
      actor_user_id,
      server_timestamp
    );

    publication_status := case
      when target_effective_at > server_timestamp then 'pending'
      else 'active'
    end;
    audit_action := 'content_published';
  end if;

  if publication_status = 'active' then
    update public.content_publications
    set status = 'retired',
        retired_at = server_timestamp,
        retired_by = actor_user_id
    where activity_id = draft_record.activity_id
      and status = 'active';
  end if;

  insert into public.content_publications (
    id,
    activity_id,
    content_version,
    version_id,
    published_by,
    published_at,
    effective_at,
    status,
    rollback_of_id
  ) values (
    new_publication_id,
    draft_record.activity_id,
    target_content_version,
    new_version_id,
    actor_user_id,
    server_timestamp,
    target_effective_at,
    publication_status,
    rollback_publication_id
  );

  insert into public.audit_log (
    actor_id,
    action,
    target_type,
    target_id,
    request_id,
    metadata
  ) values (
    actor_user_id,
    audit_action,
    'content_publication',
    new_publication_id::text,
    publication_request_id,
    pg_catalog.jsonb_strip_nulls(
      pg_catalog.jsonb_build_object(
        'activity_id', draft_record.activity_id,
        'content_version', target_content_version,
        'checksum', canonical_checksum,
        'source_draft_id', draft_record.id,
        'source_revision', draft_record.revision,
        'effective_at', target_effective_at,
        'status', publication_status,
        'rollback_of_id', rollback_publication_id,
        'validation_boundary', 'edge-typescript-v1'
      )
    )
  );

  return new_publication_id;
end;
$$;

comment on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, uuid
) is
  'Service-role-only atomic publish/rollback boundary. A rollback validates the exact historical publication/version/package identity and creates a new active pointer to that existing immutable version without inserting a duplicate version.';

create function public.activate_due_content_publication(
  target_publication_id uuid,
  activation_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  observed_activity_id text;
  publication_record public.content_publications%rowtype;
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  if activation_request_id is null then
    raise exception 'activation request id is required' using errcode = '22023';
  end if;

  select publication.activity_id
  into observed_activity_id
  from public.content_publications publication
  where publication.id = target_publication_id;

  if not found then
    raise exception 'content publication does not exist' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(observed_activity_id, 0)
  );

  select publication.*
  into publication_record
  from public.content_publications publication
  where publication.id = target_publication_id
  for update;

  if publication_record.status = 'active' then
    return publication_record.id;
  end if;
  if publication_record.status <> 'pending' then
    raise exception 'content publication is not pending' using errcode = '22023';
  end if;
  if publication_record.effective_at > server_timestamp then
    raise exception 'content publication is not due' using errcode = '22023';
  end if;

  update public.content_publications
  set status = 'retired',
      retired_at = server_timestamp,
      retired_by = publication_record.published_by
  where activity_id = publication_record.activity_id
    and status = 'active';

  update public.content_publications
  set status = 'active'
  where id = publication_record.id;

  insert into public.audit_log (
    actor_id,
    action,
    target_type,
    target_id,
    request_id,
    metadata
  ) values (
    publication_record.published_by,
    'content_publication_activated',
    'content_publication',
    publication_record.id::text,
    activation_request_id,
    pg_catalog.jsonb_build_object(
      'activity_id', publication_record.activity_id,
      'content_version', publication_record.content_version,
      'effective_at', publication_record.effective_at,
      'activation_boundary', 'service-role-worker-v1'
    )
  );

  return publication_record.id;
end;
$$;

comment on function public.activate_due_content_publication(uuid, uuid) is
  'Service-role-only worker boundary. It atomically retires the previous active pointer, activates one due pending row, and appends one audit fact. Advisory and row locks make concurrent or repeated calls idempotent.';

revoke all on function public.activate_due_content_publication(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.activate_due_content_publication(uuid, uuid)
to service_role;
