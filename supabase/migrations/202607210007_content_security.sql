-- Authenticated users author drafts, but immutable versions and publication
-- pointers are committed only by the trusted server validation workflow.

drop policy if exists content_versions_select_authenticated on public.content_versions;
drop policy if exists content_versions_insert_staff on public.content_versions;
drop policy if exists content_publications_select_authenticated on public.content_publications;
drop policy if exists content_publications_insert_owner on public.content_publications;
drop policy if exists content_publications_update_owner on public.content_publications;

revoke all on public.content_versions from authenticated;
revoke all on public.content_publications from authenticated;

revoke all on public.content_drafts from authenticated;
grant select, delete on public.content_drafts to authenticated;
grant insert (activity_id, title, package) on public.content_drafts to authenticated;
grant update (title, package) on public.content_drafts to authenticated;

create function public.protect_content_draft_metadata()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  if tg_op = 'INSERT' then
    if current_user = 'authenticated' then
      if actor_user_id is null then
        raise exception 'authenticated draft writes require auth.uid()'
          using errcode = '42501';
      end if;

      new.revision := 1;
      new.created_by := actor_user_id;
      new.updated_by := actor_user_id;
      new.created_at := server_timestamp;
      new.updated_at := server_timestamp;
      new.validation_report := null;
      new.validation_checksum := null;
    end if;
    return new;
  end if;

  if new.id is distinct from old.id
    or new.activity_id is distinct from old.activity_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'content draft identity is immutable' using errcode = 'P0001';
  end if;

  if current_user = 'authenticated' then
    if actor_user_id is null then
      raise exception 'authenticated draft writes require auth.uid()'
        using errcode = '42501';
    end if;

    new.revision := old.revision + 1;
    new.updated_by := actor_user_id;
    new.updated_at := server_timestamp;
    new.validation_report := null;
    new.validation_checksum := null;
    return new;
  end if;

  if new.title is distinct from old.title or new.package is distinct from old.package then
    if new.revision is distinct from old.revision + 1 then
      raise exception 'content draft revision must advance by exactly one'
        using errcode = 'P0001';
    end if;
  else
    new.revision := old.revision;
  end if;
  new.updated_at := server_timestamp;
  return new;
end;
$$;

create trigger content_drafts_metadata_guard
before insert or update on public.content_drafts
for each row execute function public.protect_content_draft_metadata();

create function public.get_active_content_packages()
returns table (
  activity_id text,
  content_version text,
  checksum text,
  package jsonb,
  effective_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    publication.activity_id,
    publication.content_version,
    version.checksum,
    version.package,
    publication.effective_at
  from public.content_publications publication
  join public.content_versions version
    on version.id = publication.version_id
   and version.activity_id = publication.activity_id
   and version.content_version = publication.content_version
  where publication.status = 'active'
    and publication.effective_at <= pg_catalog.statement_timestamp()
    and publication.retired_at is null
  order by publication.activity_id;
$$;

comment on function public.get_active_content_packages() is
  'Minimal device-facing content surface. Returns only packages behind currently effective active publication pointers; it exposes no draft, pending, retired, actor, or version-history rows.';

create function public.commit_validated_content_publication(
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
  new_version_id uuid := extensions.gen_random_uuid();
  new_publication_id uuid := extensions.gen_random_uuid();
  target_content_version text;
  publication_status text;
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
    or published_package ->> 'checksum' is distinct from canonical_checksum
    or published_package - 'checksum' is distinct from draft_record.package
    or published_package ->> 'activity_id' is distinct from draft_record.activity_id then
    raise exception 'validated package does not match the locked draft'
      using errcode = '22023';
  end if;

  target_content_version := published_package ->> 'content_version';
  if target_content_version is null then
    raise exception 'validated package has no content version' using errcode = '22023';
  end if;
  if target_effective_at is null then
    raise exception 'publication effective time is required' using errcode = '22023';
  end if;

  update public.content_drafts
  set validation_report = commit_validated_content_publication.validation_report,
      validation_checksum = canonical_checksum
  where id = target_draft_id;

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
    'content_published',
    'content_publication',
    new_publication_id::text,
    publication_request_id,
    pg_catalog.jsonb_build_object(
      'activity_id', draft_record.activity_id,
      'content_version', target_content_version,
      'checksum', canonical_checksum,
      'source_draft_id', draft_record.id,
      'source_revision', draft_record.revision,
      'effective_at', target_effective_at,
      'status', publication_status,
      'validation_boundary', 'edge-typescript-v1'
    )
  );

  return new_publication_id;
end;
$$;

comment on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, uuid
) is
  'Service-role-only atomic commit boundary. The caller must first run strict raw JSON parsing, the shared TypeScript schema/sample validator, and canonical SHA-256. PostgreSQL intentionally checks only transaction identities and supplied evidence; it does not claim to reproduce TypeScript canonicalization.';

revoke all on function public.protect_content_draft_metadata() from public;
revoke all on function public.get_active_content_packages() from public, anon;
revoke all on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, uuid
) from public, anon, authenticated;

grant execute on function public.get_active_content_packages()
to authenticated, service_role;
grant execute on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, uuid
) to service_role;
