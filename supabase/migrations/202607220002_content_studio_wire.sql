-- Complete the minimal Edge projections required by the strict Studio wire.
-- Immutable versions/publications remain inaccessible as raw tables.

drop function public.get_content_publication_for_rollback(uuid);

create function public.get_content_publication_for_rollback(
  target_publication_id uuid
)
returns table (
  publication_id uuid,
  activity_id text,
  content_version text,
  version_id uuid,
  checksum text,
  package jsonb,
  current_draft_id uuid,
  current_draft_revision integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    publication.id,
    publication.activity_id,
    publication.content_version,
    version.id,
    version.checksum,
    version.package,
    draft.id,
    draft.revision
  from public.content_publications publication
  join public.content_versions version
    on version.id = publication.version_id
   and version.activity_id = publication.activity_id
   and version.content_version = publication.content_version
  join public.content_drafts draft
    on draft.activity_id = publication.activity_id
  where publication.id = target_publication_id
    and publication.status = 'retired';
$$;

comment on function public.get_content_publication_for_rollback(uuid) is
  'Service-only retired publication projection with immutable package identity and the current optimistic draft revision required by validated rollback.';

revoke all on function public.get_content_publication_for_rollback(uuid)
from public, anon, authenticated;
grant execute on function public.get_content_publication_for_rollback(uuid)
to service_role;

drop function public.get_content_publication_history(text);

create function public.get_content_publication_history(target_activity_id text)
returns table (
  publication_id uuid,
  activity_id text,
  content_version text,
  checksum text,
  status text,
  actor_id uuid,
  published_at timestamptz,
  effective_at timestamptz,
  retired_at timestamptz,
  source_revision integer,
  reason text,
  validation_valid boolean,
  rollback_of_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.has_role('owner') is not true then
    raise exception 'content owner role is required to read publication history'
      using errcode = '42501';
  end if;
  if target_activity_id is not null
    and pg_catalog.char_length(target_activity_id) not between 1 and 128 then
    raise exception 'publication history activity id is invalid'
      using errcode = '22023';
  end if;

  return query
  select
    publication.id,
    publication.activity_id,
    publication.content_version,
    version.checksum,
    publication.status,
    publication.published_by,
    publication.published_at,
    publication.effective_at,
    publication.retired_at,
    version.source_revision,
    publication_audit.metadata ->> 'reason',
    coalesce(
      case publication_audit.metadata ->> 'validation_valid'
        when 'true' then true
        when 'false' then false
        else null
      end,
      false
    ),
    publication.rollback_of_id
  from public.content_publications publication
  join public.content_versions version
    on version.id = publication.version_id
   and version.activity_id = publication.activity_id
   and version.content_version = publication.content_version
  left join lateral (
    select audit.metadata
    from public.audit_log audit
    where audit.target_type = 'content_publication'
      and audit.target_id = publication.id::text
      and audit.action in ('content_published', 'content_rolled_back')
    order by audit.created_at desc, audit.id desc
    limit 1
  ) publication_audit on true
  where (target_activity_id is null or publication.activity_id = target_activity_id)
    and publication.status in ('pending', 'active', 'retired')
  order by publication.published_at desc, publication.id desc;
end;
$$;

comment on function public.get_content_publication_history(text) is
  'Owner-only strict Studio history projection. Null selects all activities, cancelled schedules are omitted, and immutable source revision is included.';

revoke all on function public.get_content_publication_history(text)
from public, anon, service_role;
grant execute on function public.get_content_publication_history(text)
to authenticated;
