-- Pairing claims are internet-facing and anonymous identities are cheap to
-- rotate. Keep a bounded, gateway-network-aware limiter inside the same
-- transaction that decides the claim outcome.

create table public.pairing_rate_limit_buckets (
  scope text not null check (scope in ('project', 'actor', 'network')),
  fingerprint bytea not null check (pg_catalog.octet_length(fingerprint) = 32),
  window_started_at timestamptz not null,
  attempt_count integer not null check (attempt_count between 0 and 1000),
  updated_at timestamptz not null,
  primary key (scope, fingerprint)
);

alter table public.pairing_rate_limit_buckets enable row level security;
alter table public.pairing_rate_limit_buckets force row level security;
revoke all on public.pairing_rate_limit_buckets from public, anon, authenticated, service_role;

comment on table public.pairing_rate_limit_buckets is
  'Private bounded pairing limiter. Network fingerprints are Edge HMAC digests; stale rows are pruned under the project claim lock.';

drop function public.claim_device_pairing_for_service(bytea, uuid, text, text);

create function public.claim_device_pairing_for_service(
  challenge_digest bytea,
  device_auth_user_id uuid,
  device_identifier text,
  profile_local_identifier text,
  device_display_name text,
  network_fingerprint bytea
)
returns table (
  outcome text,
  device_id uuid,
  family_id uuid,
  profile_id uuid,
  profile_local_id text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  pairing_record record;
  identity_device public.devices%rowtype;
  identifier_device public.devices%rowtype;
  identity_device_found boolean := false;
  identifier_device_found boolean := false;
  selected_device_id uuid;
  normalized_display_name text;
  project_fingerprint bytea := extensions.digest('pairing-project:v1', 'sha256');
  actor_fingerprint bytea;
  project_attempt_count integer := 0;
  actor_attempt_count integer := 0;
  network_attempt_count integer := 0;
  server_timestamp timestamptz := pg_catalog.clock_timestamp();
begin
  normalized_display_name := pg_catalog.regexp_replace(
    device_display_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  if pg_catalog.octet_length(challenge_digest) <> 32
    or pg_catalog.octet_length(network_fingerprint) <> 32
    or device_auth_user_id is null
    or device_identifier is null
    or pg_catalog.char_length(device_identifier) not between 1 and 128
    or profile_local_identifier is null
    or pg_catalog.char_length(profile_local_identifier) not between 1 and 128
    or normalized_display_name is null
    or pg_catalog.char_length(normalized_display_name) not between 1 and 80 then
    raise exception 'pairing claim fields are invalid' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = device_auth_user_id
      and auth_user.is_anonymous is true
  ) then
    raise exception 'pairing claimant must be an anonymous auth identity'
      using errcode = '42501';
  end if;

  actor_fingerprint := extensions.digest(device_auth_user_id::text, 'sha256');

  -- One short global critical section makes the three counters and their
  -- storage cap one atomic decision. Pairing volume is intentionally tiny.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pairing-rate-limit:project:v1', 0)
  );
  server_timestamp := pg_catalog.clock_timestamp();

  delete from public.pairing_rate_limit_buckets bucket
  where bucket.window_started_at <= server_timestamp - interval '10 minutes';

  select bucket.attempt_count
  into project_attempt_count
  from public.pairing_rate_limit_buckets bucket
  where bucket.scope = 'project'
    and bucket.fingerprint = project_fingerprint;
  project_attempt_count := coalesce(project_attempt_count, 0);
  if project_attempt_count >= 1000 then
    return query select
      'rate_limited'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  select bucket.attempt_count
  into actor_attempt_count
  from public.pairing_rate_limit_buckets bucket
  where bucket.scope = 'actor'
    and bucket.fingerprint = actor_fingerprint;
  actor_attempt_count := coalesce(actor_attempt_count, 0);
  if actor_attempt_count >= 5 then
    return query select
      'rate_limited'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  select bucket.attempt_count
  into network_attempt_count
  from public.pairing_rate_limit_buckets bucket
  where bucket.scope = 'network'
    and bucket.fingerprint = network_fingerprint;
  network_attempt_count := coalesce(network_attempt_count, 0);
  if network_attempt_count >= 5 then
    return query select
      'rate_limited'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  insert into public.pairing_rate_limit_buckets (
    scope, fingerprint, window_started_at, attempt_count, updated_at
  ) values
    ('project', project_fingerprint, server_timestamp, 1, server_timestamp),
    ('actor', actor_fingerprint, server_timestamp, 1, server_timestamp),
    ('network', network_fingerprint, server_timestamp, 1, server_timestamp)
  on conflict (scope, fingerprint) do update
  set attempt_count = public.pairing_rate_limit_buckets.attempt_count + 1,
      updated_at = excluded.updated_at;

  select
    pairing.id,
    pairing.family_id,
    pairing.profile_id,
    pairing.created_by,
    profile.client_profile_id
  into pairing_record
  from public.pairing_codes pairing
  join public.child_profiles profile
    on profile.id = pairing.profile_id
   and profile.family_id = pairing.family_id
  join public.families family on family.id = pairing.family_id
  where pairing.code_digest = challenge_digest
    and pairing.consumed_at is null
    and pairing.invalidated_at is null
    and pairing.expires_at > server_timestamp
    and pairing.attempt_count < 10
    and profile.deleted_at is null
    and family.deleted_at is null
  for update of pairing;

  if not found then
    insert into public.audit_log (
      actor_id, action, target_type, target_id, metadata, created_at
    ) values (
      device_auth_user_id,
      'pairing_claim_attempted',
      'device_auth_user',
      'anonymous-device-claim',
      pg_catalog.jsonb_build_object('outcome', 'pairing_code_invalid'),
      server_timestamp
    );
    return query select
      'pairing_code_invalid'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  -- A digest match consumes one of the challenge's own attempts regardless of
  -- the later local-profile/device decision.
  update public.pairing_codes pairing
  set attempt_count = pairing.attempt_count + 1
  where pairing.id = pairing_record.id;

  if pairing_record.client_profile_id is distinct from profile_local_identifier then
    insert into public.audit_log (
      family_id, actor_id, action, target_type, target_id, metadata, created_at
    ) values (
      pairing_record.family_id,
      device_auth_user_id,
      'pairing_claim_attempted',
      'device_auth_user',
      'anonymous-device-claim',
      pg_catalog.jsonb_build_object('outcome', 'pairing_code_invalid'),
      server_timestamp
    );
    return query select
      'pairing_code_invalid'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  select device.*
  into identity_device
  from public.devices device
  where device.auth_user_id = device_auth_user_id
  for update of device;
  identity_device_found := found;

  select device.*
  into identifier_device
  from public.devices device
  where device.device_id = device_identifier
  for update of device;
  identifier_device_found := found;

  if (
    identity_device_found and identifier_device_found
    and identity_device.id is distinct from identifier_device.id
  ) or (
    identity_device_found and (
      identity_device.family_id is distinct from pairing_record.family_id
      or identity_device.profile_id is distinct from pairing_record.profile_id
      or identity_device.device_id is distinct from device_identifier
      or identity_device.profile_local_id is distinct from profile_local_identifier
    )
  ) or (
    identifier_device_found and identifier_device.auth_user_id is distinct from device_auth_user_id
  ) then
    insert into public.audit_log (
      family_id, actor_id, action, target_type, target_id, metadata, created_at
    ) values (
      pairing_record.family_id,
      device_auth_user_id,
      'pairing_claim_attempted',
      'device_auth_user',
      'anonymous-device-claim',
      pg_catalog.jsonb_build_object('outcome', 'pairing_code_invalid'),
      server_timestamp
    );
    return query select
      'pairing_code_invalid'::text, null::uuid, null::uuid, null::uuid, null::text;
    return;
  end if;

  if identity_device_found then
    selected_device_id := identity_device.id;
    update public.devices
    set display_name = normalized_display_name,
        disconnected_at = null
    where id = selected_device_id;
  else
    selected_device_id := extensions.gen_random_uuid();
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
      selected_device_id,
      pairing_record.family_id,
      pairing_record.profile_id,
      device_auth_user_id,
      device_identifier,
      profile_local_identifier,
      normalized_display_name,
      server_timestamp
    );
  end if;

  update public.pairing_codes
  set consumed_at = server_timestamp,
      consumed_by = device_auth_user_id
  where id = pairing_record.id;

  insert into public.audit_log (
    family_id, actor_id, action, target_type, target_id, metadata, created_at
  ) values
  (
    pairing_record.family_id,
    pairing_record.created_by,
    'device_paired',
    'device',
    selected_device_id::text,
    pg_catalog.jsonb_build_object('profile_id', pairing_record.profile_id),
    server_timestamp
  ),
  (
    pairing_record.family_id,
    device_auth_user_id,
    'pairing_claim_attempted',
    'device_auth_user',
    'anonymous-device-claim',
    pg_catalog.jsonb_build_object('outcome', 'paired'),
    server_timestamp
  );

  return query select
    'paired'::text,
    selected_device_id,
    pairing_record.family_id::uuid,
    pairing_record.profile_id::uuid,
    profile_local_identifier;
end;
$$;

comment on function public.claim_device_pairing_for_service(
  bytea, uuid, text, text, text, bytea
) is
  'Service-only atomic pairing claim with explicit local profile identity, generic invalid outcomes, and bounded actor/network/project limits.';

revoke all on function public.claim_device_pairing_for_service(
  bytea, uuid, text, text, text, bytea
) from public, anon, authenticated, service_role;
grant execute on function public.claim_device_pairing_for_service(
  bytea, uuid, text, text, text, bytea
) to service_role;

-- Repair any cursor written by the historical max(sequence) implementation to
-- the actual contiguous prefix before enforcing the invariant on new writes.
with ranked_events as (
  select
    event.internal_device_id,
    event.local_sequence,
    pg_catalog.row_number() over (
      partition by event.internal_device_id
      order by event.local_sequence
    ) as ordinal
  from public.learning_events event
), contiguous_prefixes as (
  select
    device.id,
    coalesce(
      min((ranked.ordinal - 1)::bigint)
        filter (where ranked.local_sequence <> ranked.ordinal),
      max(ranked.local_sequence),
      0
    ) as contiguous_sequence
  from public.devices device
  left join ranked_events ranked on ranked.internal_device_id = device.id
  group by device.id
)
update public.devices device
set last_sequence = prefix.contiguous_sequence
from contiguous_prefixes prefix
where prefix.id = device.id
  and device.last_sequence is distinct from prefix.contiguous_sequence;

drop function public.ingest_learning_events_for_service(uuid, jsonb);

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
  next_expected_sequence bigint;
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
    device.paired_at,
    device.last_sequence
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
  next_expected_sequence := binding_record.last_sequence + 1;

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
      if parsed_sequence > binding_record.last_sequence then
        if parsed_sequence <> next_expected_sequence then
          raise exception 'new learning events must form a contiguous cursor prefix'
            using errcode = '22023';
        end if;
        next_expected_sequence := next_expected_sequence + 1;
      end if;
      event_id := parsed_event_id;
      disposition := 'already_present';
      return next;
      continue;
    end if;

    if parsed_sequence <> next_expected_sequence then
      raise exception 'new learning events must form a contiguous cursor prefix'
        using errcode = '22023';
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

    next_expected_sequence := next_expected_sequence + 1;
    event_id := parsed_event_id;
    disposition := 'accepted';
    return next;
  end loop;

  update public.devices
  set last_sequence = next_expected_sequence - 1,
      last_sync_at = greatest(server_timestamp, binding_record.paired_at)
  where id = binding_record.id;
end;
$$;

comment on function public.ingest_learning_events_for_service(uuid, jsonb) is
  'Service-only bounded idempotent ingestion. New events must extend the locked device cursor as one contiguous prefix.';

revoke all on function public.ingest_learning_events_for_service(uuid, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.ingest_learning_events_for_service(uuid, jsonb)
to service_role;
