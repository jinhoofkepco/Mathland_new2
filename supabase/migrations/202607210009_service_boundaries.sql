-- The service credential is not a trusted SQL console. Edge Functions may use
-- only the exact SECURITY DEFINER entry points granted at the end of this file.
revoke all on all tables in schema public from service_role;
revoke execute on all functions in schema public from service_role;

-- Anonymous devices and human guardians use fixed projections and targeted
-- mutations. No authenticated identity receives a raw reward relation path.
revoke all on public.guardian_rewards from authenticated;

create function public.get_device_guardian_rewards()
returns table (
  id uuid,
  title text,
  required_apples bigint,
  status text,
  created_at timestamptz,
  claimed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    reward.id,
    reward.title,
    reward.required_apples,
    reward.status,
    reward.created_at,
    reward.claimed_at
  from public.devices device
  join public.child_profiles profile
    on profile.id = device.profile_id
   and profile.family_id = device.family_id
  join public.families family on family.id = device.family_id
  join public.guardian_rewards reward
    on reward.family_id = device.family_id
   and reward.profile_id = device.profile_id
  where device.auth_user_id = auth.uid()
    and device.disconnected_at is null
    and profile.deleted_at is null
    and family.deleted_at is null
    and reward.status in ('available', 'claimed')
  order by reward.created_at, reward.id;
$$;

create function public.get_guardian_rewards(target_family_id uuid)
returns table (
  id uuid,
  profile_id uuid,
  title text,
  required_apples bigint,
  status text,
  created_at timestamptz,
  claimed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    reward.id,
    reward.profile_id,
    reward.title,
    reward.required_apples,
    reward.status,
    reward.created_at,
    reward.claimed_at
  from public.guardian_rewards reward
  where reward.family_id = target_family_id
    and public.is_family_guardian(target_family_id)
  order by reward.created_at, reward.id;
$$;

comment on function public.get_device_guardian_rewards() is
  'Device-safe reward projection. It deliberately omits family/profile and guardian auth UUIDs.';
comment on function public.get_guardian_rewards(uuid) is
  'Guardian-authorized reward projection without creator auth identity.';

create function public.create_guardian_reward(
  target_profile_id uuid,
  reward_title text,
  required_apple_count bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  target_family_id uuid;
  new_reward_id uuid := extensions.gen_random_uuid();
  normalized_title text;
begin
  normalized_title := pg_catalog.regexp_replace(
    reward_title,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  if normalized_title is null
    or pg_catalog.char_length(normalized_title) not between 1 and 120
    or required_apple_count is null
    or required_apple_count not between 0 and 9007199254740991 then
    raise exception 'guardian reward fields are invalid' using errcode = '22023';
  end if;

  select profile.family_id
  into target_family_id
  from public.child_profiles profile
  join public.families family on family.id = profile.family_id
  where profile.id = target_profile_id
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of profile;

  if not found
    or actor_user_id is null
    or public.is_family_guardian(target_family_id) is not true then
    raise exception 'guardian reward mutation is not authorized'
      using errcode = '42501';
  end if;

  insert into public.guardian_rewards (
    id,
    family_id,
    profile_id,
    title,
    required_apples,
    status,
    created_by
  ) values (
    new_reward_id,
    target_family_id,
    target_profile_id,
    normalized_title,
    required_apple_count,
    'available',
    actor_user_id
  );

  insert into public.audit_log (
    family_id, actor_id, action, target_type, target_id, metadata
  ) values (
    target_family_id,
    actor_user_id,
    'guardian_reward_created',
    'guardian_reward',
    new_reward_id::text,
    pg_catalog.jsonb_build_object(
      'profile_id', target_profile_id,
      'required_apples', required_apple_count,
      'status', 'available'
    )
  );

  return new_reward_id;
end;
$$;

create function public.update_guardian_reward(
  target_reward_id uuid,
  reward_title text,
  required_apple_count bigint,
  reward_status text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  reward_record public.guardian_rewards%rowtype;
  normalized_title text;
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  normalized_title := pg_catalog.regexp_replace(
    reward_title,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  if normalized_title is null
    or pg_catalog.char_length(normalized_title) not between 1 and 120
    or required_apple_count is null
    or required_apple_count not between 0 and 9007199254740991
    or reward_status is null
    or reward_status not in ('available', 'claimed', 'cancelled') then
    raise exception 'guardian reward fields are invalid' using errcode = '22023';
  end if;

  select reward.*
  into reward_record
  from public.guardian_rewards reward
  join public.child_profiles profile
    on profile.id = reward.profile_id
   and profile.family_id = reward.family_id
  join public.families family on family.id = reward.family_id
  where reward.id = target_reward_id
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of reward;

  if not found
    or actor_user_id is null
    or public.is_family_guardian(reward_record.family_id) is not true then
    raise exception 'guardian reward mutation is not authorized'
      using errcode = '42501';
  end if;

  update public.guardian_rewards
  set title = normalized_title,
      required_apples = required_apple_count,
      status = reward_status,
      claimed_at = case
        when reward_status = 'claimed'
          then coalesce(reward_record.claimed_at, server_timestamp)
        else null
      end
  where id = reward_record.id;

  insert into public.audit_log (
    family_id, actor_id, action, target_type, target_id, metadata
  ) values (
    reward_record.family_id,
    actor_user_id,
    'guardian_reward_updated',
    'guardian_reward',
    reward_record.id::text,
    pg_catalog.jsonb_build_object(
      'profile_id', reward_record.profile_id,
      'required_apples', required_apple_count,
      'status', reward_status
    )
  );

  return reward_record.id;
end;
$$;

create function public.delete_guardian_reward(target_reward_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := auth.uid();
  reward_record public.guardian_rewards%rowtype;
begin
  select reward.*
  into reward_record
  from public.guardian_rewards reward
  join public.child_profiles profile
    on profile.id = reward.profile_id
   and profile.family_id = reward.family_id
  join public.families family on family.id = reward.family_id
  where reward.id = target_reward_id
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of reward;

  if not found
    or actor_user_id is null
    or public.is_family_guardian(reward_record.family_id) is not true then
    raise exception 'guardian reward mutation is not authorized'
      using errcode = '42501';
  end if;

  delete from public.guardian_rewards where id = reward_record.id;

  insert into public.audit_log (
    family_id, actor_id, action, target_type, target_id, metadata
  ) values (
    reward_record.family_id,
    actor_user_id,
    'guardian_reward_deleted',
    'guardian_reward',
    reward_record.id::text,
    pg_catalog.jsonb_build_object('profile_id', reward_record.profile_id)
  );

  return reward_record.id;
end;
$$;

comment on function public.create_guardian_reward(uuid, text, bigint) is
  'Guardian-only targeted reward creation; family, actor, status, and audit identity are server-derived.';
comment on function public.update_guardian_reward(uuid, text, bigint, text) is
  'Guardian-only targeted reward update with server-derived claim time and an audit fact.';
comment on function public.delete_guardian_reward(uuid) is
  'Guardian-only targeted reward deletion with family authorization and an audit fact.';

create function public.get_content_draft_for_validation(target_draft_id uuid)
returns table (
  id uuid,
  activity_id text,
  revision integer,
  package jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select draft.id, draft.activity_id, draft.revision, draft.package
  from public.content_drafts draft
  where draft.id = target_draft_id;
$$;

create function public.get_content_publication_for_rollback(
  target_publication_id uuid
)
returns table (
  publication_id uuid,
  activity_id text,
  content_version text,
  version_id uuid,
  checksum text,
  package jsonb
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
    version.package
  from public.content_publications publication
  join public.content_versions version
    on version.id = publication.version_id
   and version.activity_id = publication.activity_id
   and version.content_version = publication.content_version
  where publication.id = target_publication_id
    and publication.status = 'retired';
$$;

create function public.get_due_content_publication_ids(batch_limit integer)
returns table (publication_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if batch_limit is null or batch_limit not between 1 and 100 then
    raise exception 'due publication batch limit must be between 1 and 100'
      using errcode = '22023';
  end if;

  return query
  select publication.id
  from public.content_publications publication
  where publication.status = 'pending'
    and publication.effective_at <= pg_catalog.statement_timestamp()
  order by publication.effective_at, publication.id
  limit batch_limit;
end;
$$;

comment on function public.get_content_draft_for_validation(uuid) is
  'Service-only minimum draft read for the TypeScript validator; raw table SELECT remains revoked.';
comment on function public.get_content_publication_for_rollback(uuid) is
  'Service-only exact historical package read used before the atomic rollback RPC.';
comment on function public.get_due_content_publication_ids(integer) is
  'Service-only bounded worker queue read; activation still requires activate_due_content_publication.';

-- A digest is globally one-time while a profile also has only one current
-- challenge. Normalize any pre-existing duplicate profile challenges before
-- installing the database invariant used in addition to the RPC lock.
with ranked_challenges as (
  select
    pairing.id,
    pg_catalog.row_number() over (
      partition by pairing.profile_id
      order by pairing.created_at desc, pairing.id desc
    ) as profile_rank
  from public.pairing_codes pairing
  where pairing.consumed_at is null
    and pairing.invalidated_at is null
)
update public.pairing_codes pairing
set invalidated_at = greatest(
  pg_catalog.statement_timestamp(),
  pairing.created_at
)
from ranked_challenges ranked
where ranked.id = pairing.id
  and ranked.profile_rank > 1;

create unique index pairing_codes_one_active_profile_idx
  on public.pairing_codes (profile_id)
  where consumed_at is null and invalidated_at is null;

create function public.create_pairing_challenge_for_service(
  target_profile_id uuid,
  challenge_digest bytea,
  challenge_expires_at timestamptz,
  actor_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_family_id uuid;
  new_pairing_id uuid := extensions.gen_random_uuid();
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  if pg_catalog.octet_length(challenge_digest) <> 32
    or challenge_expires_at <= server_timestamp
    or challenge_expires_at > server_timestamp + interval '15 minutes' then
    raise exception 'pairing challenge digest or expiry is invalid'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pairing-profile:' || target_profile_id::text, 0)
  );

  -- A waiter may have spent most of the challenge lifetime behind another
  -- creation. Re-evaluate wall-clock validity after entering the profile lock.
  server_timestamp := pg_catalog.clock_timestamp();
  if challenge_expires_at <= server_timestamp
    or challenge_expires_at > server_timestamp + interval '15 minutes' then
    raise exception 'pairing challenge digest or expiry is invalid'
      using errcode = '22023';
  end if;

  select profile.family_id
  into target_family_id
  from public.child_profiles profile
  join public.families family on family.id = profile.family_id
  where profile.id = target_profile_id
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of profile;

  if not found or not exists (
    select 1
    from public.family_memberships membership
    where membership.family_id = target_family_id
      and membership.user_id = actor_user_id
      and membership.is_active
      and membership.role in ('guardian', 'owner')
  ) then
    raise exception 'pairing actor is not authorized for this profile'
      using errcode = '42501';
  end if;

  update public.pairing_codes pairing
  set invalidated_at = greatest(server_timestamp, pairing.created_at)
  where pairing.profile_id = target_profile_id
    and pairing.consumed_at is null
    and pairing.invalidated_at is null;

  insert into public.pairing_codes (
    id,
    family_id,
    profile_id,
    code_digest,
    created_by,
    created_at,
    expires_at
  ) values (
    new_pairing_id,
    target_family_id,
    target_profile_id,
    challenge_digest,
    actor_user_id,
    server_timestamp,
    challenge_expires_at
  );

  insert into public.audit_log (
    family_id,
    actor_id,
    action,
    target_type,
    target_id,
    metadata
  ) values (
    target_family_id,
    actor_user_id,
    'pairing_challenge_created',
    'child_profile',
    target_profile_id::text,
    pg_catalog.jsonb_build_object('expires_at', challenge_expires_at)
  );

  return new_pairing_id;
end;
$$;

create function public.get_pairing_challenge_for_service(challenge_digest bytea)
returns table (
  pairing_id uuid,
  family_id uuid,
  profile_id uuid,
  expires_at timestamptz,
  attempt_count smallint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    pairing.id,
    pairing.family_id,
    pairing.profile_id,
    pairing.expires_at,
    pairing.attempt_count
  from public.pairing_codes pairing
  join public.child_profiles profile
    on profile.id = pairing.profile_id
   and profile.family_id = pairing.family_id
  join public.families family on family.id = pairing.family_id
  where pg_catalog.octet_length(challenge_digest) = 32
    and pairing.code_digest = challenge_digest
    and pairing.consumed_at is null
    and pairing.invalidated_at is null
    and pairing.expires_at > pg_catalog.statement_timestamp()
    and pairing.attempt_count < 10
    and profile.deleted_at is null
    and family.deleted_at is null;
$$;

create function public.commit_device_pairing_for_service(
  target_pairing_id uuid,
  device_auth_user_id uuid,
  device_identifier text,
  device_display_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  pairing_record record;
  new_device_id uuid := extensions.gen_random_uuid();
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  select
    pairing.id,
    pairing.family_id,
    pairing.profile_id,
    pairing.created_by,
    pairing.created_at,
    pairing.expires_at,
    pairing.consumed_at,
    pairing.invalidated_at,
    pairing.attempt_count,
    profile.client_profile_id
  into pairing_record
  from public.pairing_codes pairing
  join public.child_profiles profile
    on profile.id = pairing.profile_id
   and profile.family_id = pairing.family_id
  join public.families family on family.id = pairing.family_id
  where pairing.id = target_pairing_id
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of pairing;

  if not found
    or pairing_record.consumed_at is not null
    or pairing_record.invalidated_at is not null
    or pairing_record.expires_at <= server_timestamp
    or pairing_record.attempt_count >= 10 then
    raise exception 'pairing challenge is not active' using errcode = '22023';
  end if;

  insert into public.devices (
    id,
    family_id,
    profile_id,
    auth_user_id,
    device_id,
    profile_local_id,
    display_name,
    paired_at
  ) values (
    new_device_id,
    pairing_record.family_id,
    pairing_record.profile_id,
    device_auth_user_id,
    device_identifier,
    pairing_record.client_profile_id,
    device_display_name,
    server_timestamp
  );

  update public.pairing_codes
  set consumed_at = server_timestamp,
      consumed_by = device_auth_user_id
  where id = pairing_record.id;

  insert into public.audit_log (
    family_id,
    actor_id,
    action,
    target_type,
    target_id,
    metadata
  ) values (
    pairing_record.family_id,
    pairing_record.created_by,
    'device_paired',
    'device',
    new_device_id::text,
    pg_catalog.jsonb_build_object('profile_id', pairing_record.profile_id)
  );

  return new_device_id;
end;
$$;

create function public.ingest_learning_events_for_service(
  device_auth_user_id uuid,
  event_payloads jsonb
)
returns table (
  event_id uuid,
  disposition text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  binding_record record;
  event_payload jsonb;
  parsed_event_id uuid;
  parsed_sequence bigint;
  parsed_event_type text;
  parsed_session_id text;
  parsed_activity_id text;
  parsed_duration bigint;
  parsed_apples bigint;
  existing_device_id uuid;
  existing_payload jsonb;
  maximum_sequence bigint := 0;
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
begin
  if event_payloads is null
    or pg_catalog.jsonb_typeof(event_payloads) <> 'array'
    or pg_catalog.jsonb_array_length(event_payloads) not between 1 and 100 then
    raise exception 'event batch must contain between 1 and 100 events'
      using errcode = '22023';
  end if;

  select
    device.id,
    device.family_id,
    device.profile_id,
    device.device_id,
    device.profile_local_id,
    device.paired_at
  into binding_record
  from public.devices device
  join public.child_profiles profile
    on profile.id = device.profile_id
   and profile.family_id = device.family_id
  join public.families family on family.id = device.family_id
  where device.auth_user_id = device_auth_user_id
    and device.disconnected_at is null
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of device;

  if not found then
    raise exception 'device is not actively paired' using errcode = '42501';
  end if;

  for event_payload in
    select item.value
    from pg_catalog.jsonb_array_elements(event_payloads) with ordinality as item(value, position)
    order by item.position
  loop
    if public.learning_event_v1_is_valid(event_payload) is not true then
      raise exception 'learning event payload is invalid' using errcode = '22023';
    end if;
    if event_payload ->> 'profile_id' is distinct from binding_record.profile_local_id
      or event_payload ->> 'device_id' is distinct from binding_record.device_id then
      raise exception 'learning event does not match the bound device'
        using errcode = '42501';
    end if;

    parsed_event_id := (event_payload ->> 'event_id')::uuid;
    parsed_sequence := (event_payload ->> 'sequence')::bigint;
    maximum_sequence := greatest(maximum_sequence, parsed_sequence);

    select existing.internal_device_id, existing.payload
    into existing_device_id, existing_payload
    from public.learning_events existing
    where existing.event_id = parsed_event_id;

    if found then
      if existing_device_id is distinct from binding_record.id
        or existing_payload is distinct from event_payload then
        raise exception 'learning event id collides with different content'
          using errcode = '23505';
      end if;
      event_id := parsed_event_id;
      disposition := 'already_present';
      return next;
      continue;
    end if;

    parsed_event_type := event_payload ->> 'event_type';
    parsed_session_id := event_payload ->> 'session_id';
    parsed_activity_id := event_payload ->> 'activity_id';
    parsed_duration := case
      when parsed_event_type = 'answer_submitted'
        then (event_payload ->> 'response_duration_ms')::bigint
      else 0
    end;
    parsed_apples := case
      when parsed_event_type = 'answer_submitted'
        then coalesce((event_payload -> 'reward_delta' ->> 'apples')::bigint, 0)
      when parsed_event_type = 'run_completed'
        then coalesce((event_payload -> 'earned_rewards' ->> 'apples')::bigint, 0)
      else 0
    end;

    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    ) values (
      parsed_event_id,
      binding_record.family_id,
      binding_record.profile_id,
      binding_record.id,
      binding_record.profile_local_id,
      binding_record.device_id,
      parsed_session_id,
      parsed_sequence,
      parsed_event_type,
      parsed_activity_id,
      (event_payload ->> 'client_timestamp')::timestamptz,
      parsed_duration,
      parsed_apples,
      event_payload
    );

    event_id := parsed_event_id;
    disposition := 'accepted';
    return next;
  end loop;

  update public.devices
  set last_sequence = greatest(last_sequence, maximum_sequence),
      last_sync_at = greatest(server_timestamp, binding_record.paired_at)
  where id = binding_record.id;
end;
$$;

comment on function public.create_pairing_challenge_for_service(uuid, bytea, timestamptz, uuid) is
  'Service-only guardian-authorized creation of one bounded digest-only pairing challenge.';
comment on function public.get_pairing_challenge_for_service(bytea) is
  'Service-only lookup of active pairing metadata; it never returns the stored digest or guardian identity.';
comment on function public.commit_device_pairing_for_service(uuid, uuid, text, text) is
  'Service-only atomic challenge consumption and anonymous device binding.';
comment on function public.ingest_learning_events_for_service(uuid, jsonb) is
  'Service-only bounded, binding-derived, idempotent LearningEventV1 ingestion boundary.';

create function public.semantic_version_is_strictly_greater(
  candidate text,
  baseline text
)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  candidate_major numeric;
  candidate_minor numeric;
  candidate_patch numeric;
  baseline_major numeric;
  baseline_minor numeric;
  baseline_patch numeric;
  bounded_semver constant text := '^(0|[1-9][0-9]{0,38})\.(0|[1-9][0-9]{0,38})\.(0|[1-9][0-9]{0,38})$';
begin
  if candidate !~ bounded_semver or baseline !~ bounded_semver then
    return false;
  end if;

  candidate_major := pg_catalog.split_part(candidate, '.', 1)::numeric;
  candidate_minor := pg_catalog.split_part(candidate, '.', 2)::numeric;
  candidate_patch := pg_catalog.split_part(candidate, '.', 3)::numeric;
  baseline_major := pg_catalog.split_part(baseline, '.', 1)::numeric;
  baseline_minor := pg_catalog.split_part(baseline, '.', 2)::numeric;
  baseline_patch := pg_catalog.split_part(baseline, '.', 3)::numeric;

  return (candidate_major, candidate_minor, candidate_patch)
    > (baseline_major, baseline_minor, baseline_patch);
exception when others then
  return false;
end;
$$;

-- A cancelled schedule records when it was superseded, which can be before its
-- planned effective time. Retired publications still cannot predate activation.
alter table public.content_publications
  drop constraint content_publications_timing_check,
  add constraint content_publications_timing_check check (
    effective_at >= published_at
    and (status <> 'pending' or effective_at > published_at)
    and (retired_at is null or retired_at >= published_at)
    and (status <> 'retired' or retired_at >= effective_at)
  );

create or replace function public.activate_due_content_publication(
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
  active_record public.content_publications%rowtype;
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

  if publication_record.status in ('active', 'cancelled') then
    return publication_record.id;
  end if;
  if publication_record.status <> 'pending' then
    raise exception 'content publication is not pending' using errcode = '22023';
  end if;
  if publication_record.effective_at > server_timestamp then
    raise exception 'content publication is not due' using errcode = '22023';
  end if;

  select publication.*
  into active_record
  from public.content_publications publication
  where publication.activity_id = publication_record.activity_id
    and publication.status = 'active'
  for update;

  if found and public.semantic_version_is_strictly_greater(
    publication_record.content_version,
    active_record.content_version
  ) is not true then
    update public.content_publications
    set status = 'cancelled',
        retired_at = server_timestamp,
        retired_by = publication_record.published_by
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
      'content_publication_cancelled',
      'content_publication',
      publication_record.id::text,
      activation_request_id,
      pg_catalog.jsonb_build_object(
        'activity_id', publication_record.activity_id,
        'content_version', publication_record.content_version,
        'effective_at', publication_record.effective_at,
        'reason', 'superseded_by_newer_active_publication',
        'active_publication_id', active_record.id,
        'active_content_version', active_record.content_version,
        'activation_boundary', 'service-role-worker-v1'
      )
    );

    return publication_record.id;
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
  'Service-only due activation. It serializes by activity and cancels a stale schedule instead of replacing an equal/newer active version.';

drop function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, uuid
);

create function public.commit_validated_content_publication(
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
  normalized_reason text;
  superseded_publication record;
  server_timestamp timestamptz := pg_catalog.statement_timestamp();
  bounded_semver constant text := '^(0|[1-9][0-9]{0,38})\.(0|[1-9][0-9]{0,38})\.(0|[1-9][0-9]{0,38})$';
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
  if publication_reason is null
    or pg_catalog.char_length(publication_reason) > 500
    or publication_reason !~ '[^[:space:]]' then
    raise exception 'publication reason must contain between 1 and 500 characters'
      using errcode = '22023';
  end if;
  normalized_reason := pg_catalog.regexp_replace(
    publication_reason,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );

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
    if target_content_version !~ bounded_semver then
      raise exception 'semantic version is invalid or exceeds 39 digits per component'
        using errcode = '22023';
    end if;
    if exists (
      select 1
      from public.content_versions version
      where version.activity_id = draft_record.activity_id
        and public.semantic_version_is_strictly_greater(
          target_content_version,
          version.content_version
        ) is not true
    ) then
      raise exception 'semantic version must strictly increase for normal publication'
        using errcode = '22023';
    end if;
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

  update public.content_publications publication
  set status = 'cancelled',
      retired_at = server_timestamp,
      retired_by = actor_user_id
  where publication.activity_id = draft_record.activity_id
    and publication.status = 'pending'
  returning publication.id, publication.content_version, publication.effective_at
  into superseded_publication;

  if found then
    insert into public.audit_log (
      actor_id,
      action,
      target_type,
      target_id,
      request_id,
      metadata
    ) values (
      actor_user_id,
      'content_publication_cancelled',
      'content_publication',
      superseded_publication.id::text,
      publication_request_id,
      pg_catalog.jsonb_build_object(
        'activity_id', draft_record.activity_id,
        'content_version', superseded_publication.content_version,
        'effective_at', superseded_publication.effective_at,
        'reason', 'superseded_by_new_publication',
        'superseding_publication_id', new_publication_id,
        'superseding_content_version', target_content_version,
        'publication_boundary', 'service-role-commit-v1'
      )
    );
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
        'reason', normalized_reason,
        'validation_valid', true,
        'validation_boundary', 'edge-typescript-v1'
      )
    )
  );

  return new_publication_id;
end;
$$;

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
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'owner' then
    raise exception 'content owner role is required to read publication history'
      using errcode = '42501';
  end if;
  if target_activity_id is null
    or pg_catalog.char_length(target_activity_id) not between 1 and 128 then
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
    publication_audit.metadata ->> 'reason',
    case publication_audit.metadata ->> 'validation_valid'
      when 'true' then true
      when 'false' then false
      else null
    end,
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
  where publication.activity_id = target_activity_id
  order by publication.published_at desc, publication.id desc;
end;
$$;

comment on function public.semantic_version_is_strictly_greater(text, text) is
  'Overflow-safe numeric SemVer comparison after a bounded canonical regex check.';
comment on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) is
  'Service-only atomic publish/rollback boundary. It requires a non-whitespace human reason, cancels an existing schedule, and normal publication must be numerically greater than every historical version; lower/equal versions are reachable only through validated rollback identity.';
comment on function public.get_content_publication_history(text) is
  'Owner-only publication history projection with actor, version, checksum, lifecycle, validation status, and human reason; base tables remain private.';

revoke all on function public.get_device_guardian_rewards() from public, anon, service_role;
revoke all on function public.get_guardian_rewards(uuid) from public, anon, service_role;
revoke all on function public.create_guardian_reward(uuid, text, bigint)
from public, anon, service_role;
revoke all on function public.update_guardian_reward(uuid, text, bigint, text)
from public, anon, service_role;
revoke all on function public.delete_guardian_reward(uuid)
from public, anon, service_role;
revoke all on function public.get_content_draft_for_validation(uuid)
from public, anon, authenticated;
revoke all on function public.get_content_publication_for_rollback(uuid)
from public, anon, authenticated;
revoke all on function public.get_due_content_publication_ids(integer)
from public, anon, authenticated;
revoke all on function public.semantic_version_is_strictly_greater(text, text)
from public, anon, authenticated, service_role;
revoke all on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) from public, anon, authenticated;
revoke all on function public.get_content_publication_history(text)
from public, anon, service_role;
revoke all on function public.create_pairing_challenge_for_service(
  uuid, bytea, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function public.get_pairing_challenge_for_service(bytea)
from public, anon, authenticated;
revoke all on function public.commit_device_pairing_for_service(uuid, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.ingest_learning_events_for_service(uuid, jsonb)
from public, anon, authenticated;

grant execute on function public.get_device_guardian_rewards() to authenticated;
grant execute on function public.get_guardian_rewards(uuid) to authenticated;
grant execute on function public.create_guardian_reward(uuid, text, bigint)
to authenticated;
grant execute on function public.update_guardian_reward(uuid, text, bigint, text)
to authenticated;
grant execute on function public.delete_guardian_reward(uuid)
to authenticated;
grant execute on function public.get_content_publication_history(text) to authenticated;

grant execute on function public.get_content_draft_for_validation(uuid)
to service_role;
grant execute on function public.get_content_publication_for_rollback(uuid)
to service_role;
grant execute on function public.get_due_content_publication_ids(integer)
to service_role;
grant execute on function public.commit_validated_content_publication(
  uuid, integer, jsonb, text, jsonb, uuid, timestamptz, uuid, text, uuid
) to service_role;
grant execute on function public.activate_due_content_publication(uuid, uuid)
to service_role;
grant execute on function public.create_pairing_challenge_for_service(
  uuid, bytea, timestamptz, uuid
) to service_role;
grant execute on function public.get_pairing_challenge_for_service(bytea)
to service_role;
grant execute on function public.commit_device_pairing_for_service(uuid, uuid, text, text)
to service_role;
grant execute on function public.ingest_learning_events_for_service(uuid, jsonb)
to service_role;
