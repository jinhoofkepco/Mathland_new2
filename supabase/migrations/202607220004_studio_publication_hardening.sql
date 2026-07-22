-- Studio roles are global deployment claims. A family membership controls only
-- that family's guardian surface and must never authorize content operations.
create function public.has_global_studio_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select required_role in ('editor', 'owner')
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = required_role;
$$;

comment on function public.has_global_studio_role(text) is
  'Authenticated global Studio claim predicate. Family membership roles are intentionally ignored.';

revoke all on function public.has_global_studio_role(text)
from public, anon, service_role;
grant execute on function public.has_global_studio_role(text)
to authenticated;

drop policy if exists memberships_insert_guardian on public.family_memberships;
create policy memberships_insert_guardian on public.family_memberships
for insert to authenticated
with check (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (
    public.has_global_studio_role('owner')
    and public.is_family_member(family_id)
  )
  or (
    user_id = auth.uid()
    and role = 'guardian'
    and is_active
    and public.is_unclaimed_family_creator(family_id)
  )
);

drop policy if exists memberships_update_guardian on public.family_memberships;
create policy memberships_update_guardian on public.family_memberships
for update to authenticated
using (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (
    public.has_global_studio_role('owner')
    and public.is_family_member(family_id)
  )
)
with check (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (
    public.has_global_studio_role('owner')
    and public.is_family_member(family_id)
  )
);

drop policy if exists memberships_delete_guardian on public.family_memberships;
create policy memberships_delete_guardian on public.family_memberships
for delete to authenticated
using (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (
    public.has_global_studio_role('owner')
    and public.is_family_member(family_id)
  )
);

drop policy if exists content_drafts_select_staff on public.content_drafts;
create policy content_drafts_select_staff on public.content_drafts
for select to authenticated
using (
  public.has_global_studio_role('editor')
  or public.has_global_studio_role('owner')
);

drop policy if exists content_drafts_insert_staff on public.content_drafts;
create policy content_drafts_insert_staff on public.content_drafts
for insert to authenticated
with check (
  (
    public.has_global_studio_role('editor')
    or public.has_global_studio_role('owner')
  )
  and created_by = auth.uid()
  and updated_by = auth.uid()
);

drop policy if exists content_drafts_update_staff on public.content_drafts;
create policy content_drafts_update_staff on public.content_drafts
for update to authenticated
using (
  public.has_global_studio_role('editor')
  or public.has_global_studio_role('owner')
)
with check (
  (
    public.has_global_studio_role('editor')
    or public.has_global_studio_role('owner')
  )
  and updated_by = auth.uid()
);

drop policy if exists audit_select_scoped on public.audit_log;
create policy audit_select_scoped on public.audit_log
for select to authenticated
using (
  (family_id is not null and public.is_family_member(family_id))
  or (
    family_id is null
    and public.has_global_studio_role('owner')
  )
);

create or replace function public.get_content_publication_history(
  target_activity_id text
)
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
  if auth.uid() is null
    or public.has_global_studio_role('owner') is not true then
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
  where (
    target_activity_id is null
    or publication.activity_id = target_activity_id
  )
    and publication.status in ('pending', 'active', 'retired')
  order by publication.published_at desc, publication.id desc;
end;
$$;

comment on function public.get_content_publication_history(text) is
  'Global-owner-only strict Studio history projection. Family roles are ignored and cancelled schedules are omitted.';

revoke all on function public.get_content_publication_history(text)
from public, anon, service_role;
grant execute on function public.get_content_publication_history(text)
to authenticated;

-- A service caller cannot safely manufacture an immediate timestamp before the
-- database statement begins. Resolve immediate publish and rollback times here,
-- preserve genuinely future schedules, and return the committed lifecycle row.
create function public.commit_validated_content_publication_v2(
  target_draft_id uuid,
  expected_revision integer,
  published_package jsonb,
  canonical_checksum text,
  validation_report jsonb,
  actor_user_id uuid,
  target_effective_at timestamptz,
  publication_request_id uuid,
  publication_reason text,
  rollback_publication_id uuid
)
returns table (
  publication_id uuid,
  published_at timestamptz,
  effective_at timestamptz,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
  resolved_effective_at timestamptz;
  committed_publication_id uuid;
begin
  resolved_effective_at := case
    when rollback_publication_id is not null then server_timestamp
    when target_effective_at is null
      or target_effective_at <= server_timestamp then server_timestamp
    else target_effective_at
  end;

  committed_publication_id := public.commit_validated_content_publication(
    target_draft_id,
    expected_revision,
    published_package,
    canonical_checksum,
    validation_report,
    actor_user_id,
    resolved_effective_at,
    publication_request_id,
    publication_reason,
    rollback_publication_id
  );

  return query
  select
    publication.id,
    publication.published_at,
    publication.effective_at,
    publication.status
  from public.content_publications publication
  where publication.id = committed_publication_id;
end;
$$;

comment on function public.commit_validated_content_publication_v2(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) is
  'Service-only database-time publication wrapper. Null/past normal publication and every rollback commit immediately; future schedules preserve their requested effective instant and exact lifecycle metadata is returned.';

revoke all on function public.commit_validated_content_publication_v2(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.commit_validated_content_publication_v2(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) to service_role;
