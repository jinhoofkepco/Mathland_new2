-- This migration intentionally grants table verbs only where a policy can make
-- the verb useful. Device event writes remain RPC-only: the table has no INSERT
-- policy, even though authenticated receives INSERT so direct attempts fail at
-- the RLS boundary instead of reaching constraints.

alter table public.families enable row level security;
alter table public.families force row level security;
alter table public.family_memberships enable row level security;
alter table public.family_memberships force row level security;
alter table public.child_profiles enable row level security;
alter table public.child_profiles force row level security;
alter table public.devices enable row level security;
alter table public.devices force row level security;
alter table public.pairing_codes enable row level security;
alter table public.pairing_codes force row level security;
alter table public.learning_events enable row level security;
alter table public.learning_events force row level security;
alter table public.progress_snapshots enable row level security;
alter table public.progress_snapshots force row level security;
alter table public.reward_inventory enable row level security;
alter table public.reward_inventory force row level security;
alter table public.guardian_rewards enable row level security;
alter table public.guardian_rewards force row level security;
alter table public.content_drafts enable row level security;
alter table public.content_drafts force row level security;
alter table public.content_versions enable row level security;
alter table public.content_versions force row level security;
alter table public.content_publications enable row level security;
alter table public.content_publications force row level security;
alter table public.audit_log enable row level security;
alter table public.audit_log force row level security;

create function public.is_bound_device_profile(target_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.devices device
    join public.child_profiles profile
      on profile.id = device.profile_id
     and profile.family_id = device.family_id
    join public.families family on family.id = device.family_id
    where device.auth_user_id = auth.uid()
      and device.profile_id = target_profile_id
      and device.disconnected_at is null
      and profile.deleted_at is null
      and family.deleted_at is null
  );
$$;

create function public.is_unclaimed_family_creator(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.families family
    where family.id = target_family_id
      and family.created_by = auth.uid()
      and family.deleted_at is null
      and not exists (
        select 1
        from public.family_memberships membership
        where membership.family_id = target_family_id
      )
  );
$$;

revoke all on function public.is_bound_device_profile(uuid) from public;
revoke all on function public.is_unclaimed_family_creator(uuid) from public;
grant execute on function public.is_bound_device_profile(uuid) to authenticated, service_role;
grant execute on function public.is_unclaimed_family_creator(uuid) to authenticated, service_role;

create policy families_select_member on public.families
for select to authenticated
using (deleted_at is null and public.is_family_member(id));

create policy families_insert_creator on public.families
for insert to authenticated
with check (
  created_by = auth.uid()
  and deleted_at is null
  and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
);

create policy families_update_guardian on public.families
for update to authenticated
using (public.is_family_guardian(id))
with check (public.is_family_guardian(id));

create policy memberships_select_family on public.family_memberships
for select to authenticated
using (public.is_family_member(family_id));

create policy memberships_insert_guardian on public.family_memberships
for insert to authenticated
with check (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (public.has_role('owner') and public.is_family_member(family_id))
  or (
    user_id = auth.uid()
    and role = 'guardian'
    and is_active
    and public.is_unclaimed_family_creator(family_id)
  )
);

create policy memberships_update_guardian on public.family_memberships
for update to authenticated
using (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (public.has_role('owner') and public.is_family_member(family_id))
)
with check (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (public.has_role('owner') and public.is_family_member(family_id))
);

create policy memberships_delete_guardian on public.family_memberships
for delete to authenticated
using (
  (public.is_family_guardian(family_id) and role = 'guardian')
  or (public.has_role('owner') and public.is_family_member(family_id))
);

create policy profiles_select_guardian on public.child_profiles
for select to authenticated
using (deleted_at is null and public.is_family_guardian(family_id));

create policy profiles_insert_guardian on public.child_profiles
for insert to authenticated
with check (
  deleted_at is null
  and created_by = auth.uid()
  and public.is_family_guardian(family_id)
);

create policy profiles_update_guardian on public.child_profiles
for update to authenticated
using (deleted_at is null and public.is_family_guardian(family_id))
with check (public.is_family_guardian(family_id));

create policy devices_select_guardian_or_self on public.devices
for select to authenticated
using (
  public.is_family_guardian(family_id)
  or (auth_user_id = auth.uid() and disconnected_at is null)
);

create policy pairing_codes_select_guardian on public.pairing_codes
for select to authenticated
using (public.is_family_guardian(family_id));

create policy learning_events_select_guardian on public.learning_events
for select to authenticated
using (public.is_family_guardian(family_id));

create policy snapshots_select_guardian_or_device on public.progress_snapshots
for select to authenticated
using (
  public.is_family_guardian(family_id)
  or public.is_bound_device_profile(profile_id)
);

create policy inventory_select_guardian_or_device on public.reward_inventory
for select to authenticated
using (
  public.is_family_guardian(family_id)
  or public.is_bound_device_profile(profile_id)
);

create policy guardian_rewards_select_guardian_or_device on public.guardian_rewards
for select to authenticated
using (
  public.is_family_guardian(family_id)
  or public.is_bound_device_profile(profile_id)
);

create policy guardian_rewards_insert_guardian on public.guardian_rewards
for insert to authenticated
with check (created_by = auth.uid() and public.is_family_guardian(family_id));

create policy guardian_rewards_update_guardian on public.guardian_rewards
for update to authenticated
using (public.is_family_guardian(family_id))
with check (public.is_family_guardian(family_id));

create policy guardian_rewards_delete_guardian on public.guardian_rewards
for delete to authenticated
using (public.is_family_guardian(family_id));

create policy content_drafts_select_staff on public.content_drafts
for select to authenticated
using (public.has_role('editor') or public.has_role('owner'));

create policy content_drafts_insert_staff on public.content_drafts
for insert to authenticated
with check (
  (public.has_role('editor') or public.has_role('owner'))
  and created_by = auth.uid()
  and updated_by = auth.uid()
);

create policy content_drafts_update_staff on public.content_drafts
for update to authenticated
using (public.has_role('editor') or public.has_role('owner'))
with check (
  (public.has_role('editor') or public.has_role('owner'))
  and updated_by = auth.uid()
);

create policy content_drafts_delete_staff on public.content_drafts
for delete to authenticated
using (public.has_role('editor') or public.has_role('owner'));

create policy content_versions_select_authenticated on public.content_versions
for select to authenticated
using (true);

create policy content_versions_insert_staff on public.content_versions
for insert to authenticated
with check (
  (public.has_role('editor') or public.has_role('owner'))
  and created_by = auth.uid()
);

create policy content_publications_select_authenticated on public.content_publications
for select to authenticated
using (true);

create policy content_publications_insert_owner on public.content_publications
for insert to authenticated
with check (public.has_role('owner') and published_by = auth.uid());

create policy content_publications_update_owner on public.content_publications
for update to authenticated
using (public.has_role('owner'))
with check (
  public.has_role('owner')
  and (retired_by is null or retired_by = auth.uid())
);

create policy audit_select_scoped on public.audit_log
for select to authenticated
using (
  (family_id is not null and public.is_family_member(family_id))
  or (family_id is null and public.has_role('owner'))
);

create function public.export_family_data(target_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  family_record public.families%rowtype;
begin
  if not public.is_family_guardian(target_family_id) then
    raise exception 'not authorized to export this family' using errcode = '42501';
  end if;

  select family.*
  into strict family_record
  from public.families family
  where family.id = target_family_id
    and family.deleted_at is null;

  return jsonb_build_object(
    'schema_version', 1,
    'family', jsonb_build_object(
      'id', family_record.id,
      'name', family_record.name,
      'created_at', family_record.created_at
    ),
    'memberships', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at), '[]'::jsonb)
      from (
        select membership.user_id, membership.role, membership.is_active,
          membership.created_at, membership.revoked_at
        from public.family_memberships membership
        where membership.family_id = target_family_id
      ) export_row
    ),
    'profiles', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at), '[]'::jsonb)
      from (
        select profile.id, profile.client_profile_id, profile.nickname, profile.birth_year,
          profile.created_at, profile.updated_at
        from public.child_profiles profile
        where profile.family_id = target_family_id
          and profile.deleted_at is null
      ) export_row
    ),
    'devices', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.paired_at), '[]'::jsonb)
      from (
        select device.id, device.profile_id, device.device_id, device.profile_local_id,
          device.display_name, device.platform, device.last_sequence, device.paired_at,
          device.last_sync_at, device.disconnected_at
        from public.devices device
        where device.family_id = target_family_id
      ) export_row
    ),
    'learning_events', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.received_at, export_row.event_id), '[]'::jsonb)
      from (
        select event.event_id, event.cloud_profile_id as profile_id, event.device_id,
          event.session_id, event.local_sequence, event.event_type, event.activity_id,
          event.client_timestamp, event.response_duration_ms, event.reward_apples,
          event.payload, event.received_at
        from public.learning_events event
        where event.family_id = target_family_id
      ) export_row
    ),
    'progress_snapshots', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.updated_at), '[]'::jsonb)
      from (
        select snapshot.profile_id, snapshot.device_id, snapshot.through_sequence,
          snapshot.snapshot, snapshot.created_at, snapshot.updated_at
        from public.progress_snapshots snapshot
        where snapshot.family_id = target_family_id
      ) export_row
    ),
    'reward_inventory', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.profile_id, export_row.reward_id), '[]'::jsonb)
      from (
        select inventory.profile_id, inventory.reward_id, inventory.quantity, inventory.updated_at
        from public.reward_inventory inventory
        where inventory.family_id = target_family_id
      ) export_row
    ),
    'guardian_rewards', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at), '[]'::jsonb)
      from (
        select reward.id, reward.profile_id, reward.title, reward.required_apples,
          reward.status, reward.created_at, reward.claimed_at
        from public.guardian_rewards reward
        where reward.family_id = target_family_id
      ) export_row
    ),
    'audit_log', (
      select coalesce(jsonb_agg(to_jsonb(export_row) order by export_row.created_at, export_row.id), '[]'::jsonb)
      from (
        select audit.id, audit.actor_id, audit.action, audit.target_type, audit.target_id,
          audit.request_id, audit.metadata, audit.created_at
        from public.audit_log audit
        where audit.family_id = target_family_id
      ) export_row
    )
  );
exception
  when no_data_found then
    raise exception 'not authorized to export this family' using errcode = '42501';
end;
$$;

create function public.delete_child_profile(
  target_profile_id uuid,
  confirmation_nickname text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_record public.child_profiles%rowtype;
  actor_user_id uuid := auth.uid();
  profile_hash text;
  deleted_event_count bigint;
begin
  select profile.*
  into profile_record
  from public.child_profiles profile
  where profile.id = target_profile_id
    and profile.deleted_at is null
  for update;

  if not found or not public.is_family_guardian(profile_record.family_id) then
    raise exception 'not authorized to delete this profile' using errcode = '42501';
  end if;
  if confirmation_nickname is distinct from profile_record.nickname then
    raise exception 'profile nickname confirmation does not match' using errcode = '22023';
  end if;

  update public.pairing_codes pairing
  set invalidated_at = greatest(
    pg_catalog.statement_timestamp(),
    pairing.created_at
  )
  where pairing.profile_id = target_profile_id
    and pairing.consumed_at is null
    and pairing.invalidated_at is null;

  update public.devices device
  set disconnected_at = greatest(
    pg_catalog.statement_timestamp(),
    device.paired_at
  )
  where device.profile_id = target_profile_id
    and device.disconnected_at is null;

  deleted_event_count := public.delete_learning_events_for_profile_internal(
    target_profile_id
  );

  delete from public.child_profiles
  where id = target_profile_id;

  profile_hash := pg_catalog.encode(
    extensions.digest(target_profile_id::text, 'sha256'),
    'hex'
  );
  insert into public.audit_log (
    family_id,
    actor_id,
    action,
    target_type,
    target_id,
    metadata
  ) values (
    profile_record.family_id,
    actor_user_id,
    'profile_deleted',
    'child_profile',
    profile_hash,
    jsonb_build_object(
      'profile_hash', profile_hash,
      'deleted_event_count', deleted_event_count
    )
  );
end;
$$;

revoke all on all tables in schema public from anon, authenticated;

grant select, insert, update on public.families to authenticated;
grant select, insert, update, delete on public.family_memberships to authenticated;
grant select, insert, update on public.child_profiles to authenticated;
grant select on public.devices, public.pairing_codes to authenticated;
grant select, insert on public.learning_events to authenticated;
grant select on public.progress_snapshots, public.reward_inventory to authenticated;
grant select, insert, update, delete on public.guardian_rewards to authenticated;
grant select, insert, update, delete on public.content_drafts to authenticated;
grant select, insert on public.content_versions to authenticated;
grant select, insert, update on public.content_publications to authenticated;
grant select, insert on public.audit_log to authenticated;
grant select on
  public.guardian_session_summary,
  public.guardian_activity_summary,
  public.guardian_error_patterns,
  public.guardian_reward_summary,
  public.guardian_profile_sync_summary
to authenticated;

grant all privileges on all tables in schema public to service_role;

revoke execute on all functions in schema public from public;
alter default privileges in schema public revoke execute on functions from public;

grant execute on function public.is_family_member(uuid) to authenticated, service_role;
grant execute on function public.is_family_guardian(uuid) to authenticated, service_role;
grant execute on function public.has_role(text) to authenticated, service_role;
grant execute on function public.is_bound_device_profile(uuid) to authenticated, service_role;
grant execute on function public.is_unclaimed_family_creator(uuid) to authenticated, service_role;
grant execute on function public.export_family_data(uuid) to authenticated, service_role;
grant execute on function public.delete_child_profile(uuid, text) to authenticated, service_role;

grant execute on all functions in schema public to service_role;
