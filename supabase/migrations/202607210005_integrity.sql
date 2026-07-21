-- Cross-runtime data integrity and narrowly scoped lifecycle primitives.
-- RLS policies, public guardian RPCs, and table grants are intentionally owned
-- by the following migration.

create function public.jsonb_is_safe_integer(
  candidate jsonb,
  minimum_value bigint,
  maximum_value bigint
)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  numeric_value numeric;
begin
  if pg_catalog.jsonb_typeof(candidate) <> 'number' then
    return false;
  end if;

  numeric_value := (candidate #>> '{}')::numeric;
  return numeric_value = pg_catalog.trunc(numeric_value)
    and numeric_value between minimum_value and maximum_value;
exception when others then
  return false;
end;
$$;

create function public.jsonb_is_nonempty_string(candidate jsonb)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.jsonb_typeof(candidate) = 'string'
    and pg_catalog.char_length(candidate #>> '{}') >= 1;
$$;

create function public.jsonb_has_shape(
  candidate jsonb,
  required_keys text[],
  optional_keys text[]
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.jsonb_typeof(candidate) = 'object'
    and candidate ?& required_keys
    and candidate - (required_keys || optional_keys) = '{}'::jsonb;
$$;

create function public.jsonb_is_answer_value_v1(candidate jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  element jsonb;
  answer_kind text;
begin
  if public.jsonb_is_safe_integer(
    candidate,
    -9007199254740991,
    9007199254740991
  ) is true then
    return true;
  end if;

  if pg_catalog.jsonb_typeof(candidate) <> 'object'
    or public.jsonb_is_nonempty_string(candidate -> 'kind') is not true then
    return false;
  end if;

  answer_kind := candidate ->> 'kind';
  if answer_kind = 'integer' then
    return public.jsonb_has_shape(
      candidate,
      array['kind', 'value'],
      array[]::text[]
    ) is true
      and public.jsonb_is_safe_integer(
        candidate -> 'value',
        -9007199254740991,
        9007199254740991
      ) is true;
  end if;

  if answer_kind <> 'integer_list'
    or public.jsonb_has_shape(
      candidate,
      array['kind', 'values', 'order_matters'],
      array[]::text[]
    ) is not true
    or pg_catalog.jsonb_typeof(candidate -> 'values') <> 'array'
    or pg_catalog.jsonb_typeof(candidate -> 'order_matters') <> 'boolean' then
    return false;
  end if;

  for element in
    select value
    from pg_catalog.jsonb_array_elements(candidate -> 'values') as items(value)
  loop
    if public.jsonb_is_safe_integer(
      element,
      -9007199254740991,
      9007199254740991
    ) is not true then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create function public.jsonb_is_resolved_parameters_v1(candidate jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  parameter_key text;
  parameter_value jsonb;
  array_value jsonb;
  numeric_value numeric;
begin
  if pg_catalog.jsonb_typeof(candidate) <> 'object' then
    return false;
  end if;

  for parameter_key, parameter_value in
    select key, value from pg_catalog.jsonb_each(candidate)
  loop
    if pg_catalog.char_length(parameter_key) < 1 then
      return false;
    end if;

    if pg_catalog.jsonb_typeof(parameter_value) in ('string', 'boolean') then
      continue;
    end if;

    if pg_catalog.jsonb_typeof(parameter_value) = 'number' then
      numeric_value := (parameter_value #>> '{}')::numeric;
      if numeric_value between -9007199254740991 and 9007199254740991 then
        continue;
      end if;
      return false;
    end if;

    if pg_catalog.jsonb_typeof(parameter_value) <> 'array' then
      return false;
    end if;

    for array_value in
      select value
      from pg_catalog.jsonb_array_elements(parameter_value) as items(value)
    loop
      if pg_catalog.jsonb_typeof(array_value) <> 'number' then
        return false;
      end if;
      numeric_value := (array_value #>> '{}')::numeric;
      if numeric_value not between -9007199254740991 and 9007199254740991 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
exception when others then
  return false;
end;
$$;

create function public.jsonb_is_reward_map_v1(candidate jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  reward_key text;
  reward_value jsonb;
begin
  if pg_catalog.jsonb_typeof(candidate) <> 'object' then
    return false;
  end if;

  for reward_key, reward_value in
    select key, value from pg_catalog.jsonb_each(candidate)
  loop
    if pg_catalog.char_length(reward_key) < 1
      or public.jsonb_is_safe_integer(
        reward_value,
        0,
        9007199254740991
      ) is not true then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create function public.learning_event_timestamp_is_valid(candidate text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  parsed_timestamp timestamptz;
begin
  if candidate !~ '^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$' then
    return false;
  end if;

  parsed_timestamp := candidate::timestamptz;
  return pg_catalog.to_char(
    parsed_timestamp at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS"Z"'
  ) = candidate;
exception when others then
  return false;
end;
$$;

create function public.learning_event_v1_is_valid(payload jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  event_type_value text;
  common_keys constant text[] := array[
    'contract_version',
    'event_id',
    'profile_id',
    'device_id',
    'sequence',
    'client_timestamp',
    'event_type'
  ];
begin
  if pg_catalog.jsonb_typeof(payload) <> 'object'
    or not (payload ?& common_keys)
    or public.jsonb_is_safe_integer(payload -> 'contract_version', 1, 1) is not true
    or public.jsonb_is_nonempty_string(payload -> 'event_id') is not true
    or (payload ->> 'event_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or public.jsonb_is_nonempty_string(payload -> 'profile_id') is not true
    or public.jsonb_is_nonempty_string(payload -> 'device_id') is not true
    or public.jsonb_is_safe_integer(
      payload -> 'sequence',
      1,
      9007199254740991
    ) is not true
    or public.jsonb_is_nonempty_string(payload -> 'client_timestamp') is not true
    or public.learning_event_timestamp_is_valid(payload ->> 'client_timestamp') is not true
    or public.jsonb_is_nonempty_string(payload -> 'event_type') is not true then
    return false;
  end if;

  event_type_value := payload ->> 'event_type';
  if event_type_value = 'run_started' then
    return public.jsonb_has_shape(
      payload,
      common_keys || array['session_id', 'activity_id', 'content_version'],
      array[]::text[]
    ) is true
      and public.jsonb_is_nonempty_string(payload -> 'session_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'activity_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'content_version') is true;
  end if;

  if event_type_value = 'answer_submitted' then
    return public.jsonb_has_shape(
      payload,
      common_keys || array[
        'session_id',
        'activity_id',
        'content_version',
        'question_seed',
        'generator_id',
        'band_id',
        'resolved_parameters',
        'submitted_answer',
        'correct_answer',
        'correctness',
        'response_duration_ms',
        'hints',
        'health_delta',
        'combo',
        'reward_delta'
      ],
      array[]::text[]
    ) is true
      and public.jsonb_is_nonempty_string(payload -> 'session_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'activity_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'content_version') is true
      and public.jsonb_is_safe_integer(payload -> 'question_seed', 0, 9007199254740991) is true
      and public.jsonb_is_nonempty_string(payload -> 'generator_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'band_id') is true
      and public.jsonb_is_resolved_parameters_v1(payload -> 'resolved_parameters') is true
      and public.jsonb_is_answer_value_v1(payload -> 'submitted_answer') is true
      and public.jsonb_is_answer_value_v1(payload -> 'correct_answer') is true
      and pg_catalog.jsonb_typeof(payload -> 'correctness') = 'boolean'
      and public.jsonb_is_safe_integer(payload -> 'response_duration_ms', 0, 9007199254740991) is true
      and public.jsonb_is_safe_integer(payload -> 'hints', 0, 9007199254740991) is true
      and public.jsonb_is_safe_integer(payload -> 'health_delta', -9007199254740991, 9007199254740991) is true
      and public.jsonb_is_safe_integer(payload -> 'combo', 0, 9007199254740991) is true
      and public.jsonb_is_reward_map_v1(payload -> 'reward_delta') is true;
  end if;

  if event_type_value = 'run_completed' then
    return public.jsonb_has_shape(
      payload,
      common_keys || array[
        'session_id',
        'completion_reason',
        'final_score',
        'final_health',
        'earned_rewards'
      ],
      array[]::text[]
    ) is true
      and public.jsonb_is_nonempty_string(payload -> 'session_id') is true
      and public.jsonb_is_nonempty_string(payload -> 'completion_reason') is true
      and public.jsonb_is_safe_integer(payload -> 'final_score', 0, 9007199254740991) is true
      and public.jsonb_is_safe_integer(payload -> 'final_health', 0, 9007199254740991) is true
      and public.jsonb_is_reward_map_v1(payload -> 'earned_rewards') is true;
  end if;

  if event_type_value = 'collection_unlocked' then
    return public.jsonb_has_shape(
      payload,
      common_keys || array['collection_id'],
      array['session_id']
    ) is true
      and public.jsonb_is_nonempty_string(payload -> 'collection_id') is true
      and (
        not (payload ? 'session_id')
        or public.jsonb_is_nonempty_string(payload -> 'session_id') is true
      );
  end if;

  if event_type_value = 'coupon_earned' then
    return public.jsonb_has_shape(
      payload,
      common_keys || array['coupon_id'],
      array['session_id']
    ) is true
      and public.jsonb_is_nonempty_string(payload -> 'coupon_id') is true
      and (
        not (payload ? 'session_id')
        or public.jsonb_is_nonempty_string(payload -> 'session_id') is true
      );
  end if;

  return false;
exception when others then
  return false;
end;
$$;

create function public.learning_event_v1_matches_columns(
  payload jsonb,
  row_event_id uuid,
  row_profile_id text,
  row_device_id text,
  row_session_id text,
  row_sequence bigint,
  row_event_type text,
  row_activity_id text,
  row_client_timestamp timestamptz,
  row_response_duration_ms bigint,
  row_reward_apples bigint
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  expected_duration bigint := 0;
  expected_apples bigint := 0;
begin
  if public.learning_event_v1_is_valid(payload) is not true then
    return false;
  end if;

  if row_event_type = 'answer_submitted' then
    expected_duration := (payload ->> 'response_duration_ms')::bigint;
    expected_apples := coalesce(
      (payload -> 'reward_delta' ->> 'apples')::bigint,
      0
    );
  elsif row_event_type = 'run_completed' then
    expected_apples := coalesce(
      (payload -> 'earned_rewards' ->> 'apples')::bigint,
      0
    );
  end if;

  return (payload ->> 'event_id') = row_event_id::text
    and (payload ->> 'profile_id') = row_profile_id
    and (payload ->> 'device_id') = row_device_id
    and (payload ->> 'session_id') is not distinct from row_session_id
    and (payload ->> 'sequence')::bigint = row_sequence
    and (payload ->> 'event_type') = row_event_type
    and (payload ->> 'activity_id') is not distinct from row_activity_id
    and (payload ->> 'client_timestamp')::timestamptz = row_client_timestamp
    and expected_duration = row_response_duration_ms
    and expected_apples = row_reward_apples;
exception when others then
  return false;
end;
$$;

alter table public.child_profiles
  add constraint child_profiles_id_family_key unique (id, family_id),
  add constraint child_profiles_binding_key unique (
    id,
    family_id,
    client_profile_id
  );

alter table public.devices
  drop constraint devices_profile_id_fkey,
  add constraint devices_profile_identity_key unique (id, family_id, profile_id),
  add constraint devices_event_binding_key unique (
    id,
    device_id,
    family_id,
    profile_id,
    profile_local_id
  ),
  add constraint devices_profile_binding_fkey
    foreign key (profile_id, family_id, profile_local_id)
    references public.child_profiles(id, family_id, client_profile_id)
    on delete cascade;

alter table public.pairing_codes
  drop constraint pairing_codes_profile_id_fkey,
  add constraint pairing_codes_profile_family_fkey
    foreign key (profile_id, family_id)
    references public.child_profiles(id, family_id)
    on delete cascade;

alter table public.learning_events
  drop constraint learning_events_cloud_profile_id_fkey,
  drop constraint learning_events_device_binding_fkey,
  drop constraint learning_events_payload_check1,
  drop constraint learning_events_check,
  drop constraint learning_events_check1,
  drop constraint learning_events_check2,
  drop constraint learning_events_check3,
  drop constraint learning_events_check4,
  add constraint learning_events_device_binding_fkey
    foreign key (
      internal_device_id,
      device_id,
      family_id,
      cloud_profile_id,
      profile_id
    )
    references public.devices(
      id,
      device_id,
      family_id,
      profile_id,
      profile_local_id
    )
    on delete cascade,
  add constraint learning_events_payload_v1_check check (
    public.learning_event_v1_matches_columns(
      payload,
      event_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples
    ) is true
  ),
  add constraint learning_events_duration_safe_check check (
    response_duration_ms between 0 and 9007199254740991
  ),
  add constraint learning_events_reward_safe_check check (
    reward_apples between 0 and 9007199254740991
  );

alter table public.progress_snapshots
  drop constraint progress_snapshots_profile_id_fkey,
  drop constraint progress_snapshots_device_id_fkey,
  add constraint progress_snapshots_device_binding_fkey
    foreign key (device_id, family_id, profile_id)
    references public.devices(id, family_id, profile_id)
    on delete cascade;

alter table public.reward_inventory
  drop constraint reward_inventory_profile_id_fkey,
  add constraint reward_inventory_profile_family_fkey
    foreign key (profile_id, family_id)
    references public.child_profiles(id, family_id)
    on delete cascade;

alter table public.guardian_rewards
  drop constraint guardian_rewards_profile_id_fkey,
  add constraint guardian_rewards_profile_family_fkey
    foreign key (profile_id, family_id)
    references public.child_profiles(id, family_id)
    on delete cascade;

alter table public.pairing_codes
  add column invalidated_at timestamptz,
  add constraint pairing_codes_consumption_state_check check (
    (consumed_at is null) = (consumed_by is null)
    and (
      consumed_at is null
      or consumed_at between created_at and expires_at
    )
    and (invalidated_at is null or invalidated_at >= created_at)
    and not (consumed_at is not null and invalidated_at is not null)
  );

create unique index pairing_codes_active_digest_idx
  on public.pairing_codes (code_digest)
  where consumed_at is null and invalidated_at is null;

create or replace function public.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  relation_owner oid;
  profile_delete_id text;
  audit_identity_unchanged boolean;
  audit_actor_anonymized boolean;
  audit_family_anonymized boolean;
begin
  if tg_op = 'TRUNCATE' then
    raise exception '% is append-only', tg_table_name using errcode = 'P0001';
  end if;

  if tg_table_name = 'learning_events' and tg_op = 'DELETE' then
    select relation.relowner
    into relation_owner
    from pg_catalog.pg_class relation
    where relation.oid = tg_relid;

    profile_delete_id := pg_catalog.current_setting(
      'mathland.deleting_profile_id',
      true
    );
    if pg_catalog.to_regrole(current_user)::oid = relation_owner
      and profile_delete_id = old.cloud_profile_id::text then
      return old;
    end if;
  end if;

  if tg_table_name = 'audit_log'
    and tg_op = 'UPDATE'
    and pg_catalog.pg_trigger_depth() > 1 then
    audit_identity_unchanged := (
      pg_catalog.to_jsonb(new) - array['actor_id', 'family_id']
    ) = (
      pg_catalog.to_jsonb(old) - array['actor_id', 'family_id']
    );
    audit_actor_anonymized := new.actor_id is not distinct from old.actor_id
      or (old.actor_id is not null and new.actor_id is null);
    audit_family_anonymized := new.family_id is not distinct from old.family_id
      or (old.family_id is not null and new.family_id is null);

    if audit_identity_unchanged
      and audit_actor_anonymized
      and audit_family_anonymized
      and (
        new.actor_id is distinct from old.actor_id
        or new.family_id is distinct from old.family_id
      ) then
      return new;
    end if;
  end if;

  raise exception '% is append-only', tg_table_name using errcode = 'P0001';
end;
$$;

create function public.delete_learning_events_for_profile_internal(
  target_profile_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count bigint;
begin
  perform pg_catalog.set_config(
    'mathland.deleting_profile_id',
    target_profile_id::text,
    true
  );

  delete from public.learning_events
  where cloud_profile_id = target_profile_id;
  get diagnostics deleted_count = row_count;

  perform pg_catalog.set_config('mathland.deleting_profile_id', '', true);
  return deleted_count;
exception when others then
  perform pg_catalog.set_config('mathland.deleting_profile_id', '', true);
  raise;
end;
$$;

revoke all
on function public.delete_learning_events_for_profile_internal(uuid)
from public;

create trigger learning_events_append_only_truncate
before truncate on public.learning_events
for each statement execute function public.reject_append_only_mutation();

create trigger audit_log_append_only_truncate
before truncate on public.audit_log
for each statement execute function public.reject_append_only_mutation();

create trigger content_versions_append_only_truncate
before truncate on public.content_versions
for each statement execute function public.reject_append_only_mutation();

alter table public.content_publications
  add column status text not null default 'active',
  add column effective_at timestamptz not null default now();

update public.content_publications
set status = case when retired_at is null then 'active' else 'retired' end,
    effective_at = published_at;

drop index public.content_publications_one_active_idx;

alter table public.content_publications
  drop constraint content_publications_rollback_of_id_fkey,
  add constraint content_publications_identity_key unique (id, activity_id),
  add constraint content_publications_rollback_identity_fkey
    foreign key (rollback_of_id, activity_id)
    references public.content_publications(id, activity_id)
    on delete restrict,
  add constraint content_publications_not_self_rollback_check check (
    rollback_of_id is null or rollback_of_id <> id
  ),
  add constraint content_publications_lifecycle_check check (
    (
      status in ('active', 'pending')
      and retired_at is null
      and retired_by is null
    )
    or (
      status in ('retired', 'cancelled')
      and retired_at is not null
      and retired_by is not null
    )
  ),
  add constraint content_publications_timing_check check (
    effective_at >= published_at
    and (status <> 'pending' or effective_at > published_at)
    and (retired_at is null or retired_at >= effective_at)
  );

create unique index content_publications_one_active_idx
  on public.content_publications (activity_id)
  where status = 'active';

create unique index content_publications_one_pending_idx
  on public.content_publications (activity_id)
  where status = 'pending';

create function public.protect_content_publication_history()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if (new.status = 'pending' and new.effective_at <= pg_catalog.statement_timestamp())
      or (new.status = 'active' and new.effective_at > pg_catalog.statement_timestamp()) then
      raise exception 'publication status does not match its effective time'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if tg_op in ('DELETE', 'TRUNCATE') then
    raise exception 'content_publications is append-only' using errcode = 'P0001';
  end if;

  if new.id is distinct from old.id
    or new.activity_id is distinct from old.activity_id
    or new.content_version is distinct from old.content_version
    or new.version_id is distinct from old.version_id
    or new.published_by is distinct from old.published_by
    or new.published_at is distinct from old.published_at
    or new.effective_at is distinct from old.effective_at
    or new.rollback_of_id is distinct from old.rollback_of_id then
    raise exception 'content publication identity is immutable' using errcode = 'P0001';
  end if;

  if old.status = 'active' and new.status = 'retired' then
    return new;
  end if;

  if old.status = 'pending'
    and new.status = 'active'
    and new.effective_at > pg_catalog.statement_timestamp() then
    raise exception 'publication status does not match its effective time'
      using errcode = '23514';
  end if;

  if old.status = 'pending' and new.status in ('active', 'cancelled') then
    return new;
  end if;

  raise exception 'invalid content publication lifecycle transition'
    using errcode = 'P0001';
end;
$$;

create trigger content_publications_history_guard
before insert or update or delete on public.content_publications
for each row execute function public.protect_content_publication_history();

create trigger content_publications_history_truncate_guard
before truncate on public.content_publications
for each statement execute function public.protect_content_publication_history();

create or replace function public.is_family_member(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_memberships membership
    join public.families family on family.id = membership.family_id
    where membership.family_id = target_family_id
      and membership.user_id = auth.uid()
      and membership.is_active
      and family.deleted_at is null
  );
$$;

create or replace function public.is_family_guardian(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_memberships membership
    join public.families family on family.id = membership.family_id
    where membership.family_id = target_family_id
      and membership.user_id = auth.uid()
      and membership.is_active
      and membership.role in ('guardian', 'owner')
      and family.deleted_at is null
  );
$$;

create or replace function public.has_role(required_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = required_role
    or exists (
      select 1
      from public.family_memberships membership
      join public.families family on family.id = membership.family_id
      where membership.user_id = auth.uid()
        and membership.is_active
        and membership.role = required_role
        and family.deleted_at is null
    );
$$;

create or replace view public.guardian_session_summary
with (security_invoker = true)
as
select
  event.family_id,
  event.cloud_profile_id as profile_id,
  event.session_id,
  min(event.client_timestamp)
    filter (where event.event_type = 'run_started') as started_at,
  max(event.client_timestamp)
    filter (where event.event_type = 'run_completed') as completed_at,
  max((event.payload ->> 'final_score')::bigint)
    filter (where event.event_type = 'run_completed') as final_score,
  max((event.payload ->> 'final_health')::bigint)
    filter (where event.event_type = 'run_completed') as final_health,
  count(*) filter (where event.event_type = 'answer_submitted') as answer_count,
  count(*) filter (
    where event.event_type = 'answer_submitted'
      and (event.payload ->> 'correctness')::boolean
  ) as correct_count
from public.learning_events event
where event.session_id is not null
group by event.family_id, event.cloud_profile_id, event.session_id
having count(*) filter (where event.event_type = 'run_started') > 0
  and count(*) filter (where event.event_type = 'run_completed') > 0;

create view public.guardian_profile_sync_summary
with (security_invoker = true)
as
select
  profile.family_id,
  profile.id as profile_id,
  sync.latest_sync_at,
  sync.latest_sync_at is null
    or sync.latest_sync_at < pg_catalog.statement_timestamp() - interval '24 hours'
    as is_stale
from public.child_profiles profile
join public.families family
  on family.id = profile.family_id
 and family.deleted_at is null
left join lateral (
  select max(device.last_sync_at) as latest_sync_at
  from public.devices device
  where device.family_id = profile.family_id
    and device.profile_id = profile.id
    and device.disconnected_at is null
) sync on true
where profile.deleted_at is null;

comment on view public.guardian_profile_sync_summary is
  'Latest connected-device sync per child; stale means no sync or more than 24 server hours.';
