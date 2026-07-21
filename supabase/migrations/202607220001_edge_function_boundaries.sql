-- Edge Functions never receive raw table privileges. These two SECURITY DEFINER
-- functions are the complete service-role mutation boundary for device claims
-- and the response-producing ingestion transaction.

create index audit_log_pairing_claim_actor_created_idx
  on public.audit_log (actor_id, created_at desc)
  where action = 'pairing_claim_attempted';

create function public.claim_device_pairing_for_service(
  challenge_digest bytea,
  device_auth_user_id uuid,
  device_identifier text,
  device_display_name text
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
  recent_attempt_count bigint;
  server_timestamp timestamptz := pg_catalog.clock_timestamp();
begin
  normalized_display_name := pg_catalog.regexp_replace(
    device_display_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  if pg_catalog.octet_length(challenge_digest) <> 32
    or device_auth_user_id is null
    or device_identifier is null
    or pg_catalog.char_length(device_identifier) not between 1 and 128
    or normalized_display_name is null
    or pg_catalog.char_length(normalized_display_name) not between 1 and 80 then
    raise exception 'pairing claim fields are invalid' using errcode = '22023';
  end if;

  -- Edge verification is repeated at the database trust boundary. Human
  -- identities can never be converted into child-device bindings.
  if not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = device_auth_user_id
      and auth_user.is_anonymous is true
  ) then
    raise exception 'pairing claimant must be an anonymous auth identity'
      using errcode = '42501';
  end if;

  -- Serialize each anonymous identity before counting immutable attempt facts.
  -- Returning an outcome (rather than raising) ensures rejected attempts commit
  -- and therefore cannot fail open in production.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pairing-claim:' || device_auth_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('pairing-device:' || device_identifier, 0)
  );
  server_timestamp := pg_catalog.clock_timestamp();

  select pg_catalog.count(*)
  into recent_attempt_count
  from public.audit_log audit
  where audit.actor_id = device_auth_user_id
    and audit.action = 'pairing_claim_attempted'
    and audit.created_at > server_timestamp - interval '10 minutes';

  if recent_attempt_count >= 5 then
    insert into public.audit_log (
      actor_id, action, target_type, target_id, metadata, created_at
    ) values (
      device_auth_user_id,
      'pairing_claim_attempted',
      'device_auth_user',
      'anonymous-device-claim',
      pg_catalog.jsonb_build_object('outcome', 'rate_limited'),
      server_timestamp
    );
    return query select
      'rate_limited'::text,
      null::uuid,
      null::uuid,
      null::uuid,
      null::text;
    return;
  end if;

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
      'pairing_code_invalid'::text,
      null::uuid,
      null::uuid,
      null::uuid,
      null::text;
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
      or identity_device.profile_local_id is distinct from pairing_record.client_profile_id
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
      pg_catalog.jsonb_build_object('outcome', 'device_already_paired'),
      server_timestamp
    );
    return query select
      'device_already_paired'::text,
      null::uuid,
      null::uuid,
      null::uuid,
      null::text;
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
      pairing_record.client_profile_id,
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
    pairing_record.client_profile_id::text;
end;
$$;

comment on function public.claim_device_pairing_for_service(bytea, uuid, text, text) is
  'Service-only atomic anonymous-device claim with a persisted sliding 10-minute, five-attempt limit and non-enumerating outcomes.';

create function public.ingest_learning_event_batch_for_service(
  device_auth_user_id uuid,
  event_payloads jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ingest_result record;
  accepted_ids jsonb := '[]'::jsonb;
  already_present_ids jsonb := '[]'::jsonb;
  authoritative_cursor bigint;
begin
  for ingest_result in
    select result.event_id, result.disposition
    from public.ingest_learning_events_for_service(
      device_auth_user_id,
      event_payloads
    ) result
  loop
    if ingest_result.disposition = 'accepted' then
      accepted_ids := accepted_ids || pg_catalog.jsonb_build_array(
        ingest_result.event_id::text
      );
    elsif ingest_result.disposition = 'already_present' then
      already_present_ids := already_present_ids || pg_catalog.jsonb_build_array(
        ingest_result.event_id::text
      );
    else
      raise exception 'ingest boundary returned an invalid disposition'
        using errcode = 'XX000';
    end if;
  end loop;

  select device.last_sequence
  into authoritative_cursor
  from public.devices device
  join public.child_profiles profile
    on profile.id = device.profile_id
   and profile.family_id = device.family_id
  join public.families family on family.id = device.family_id
  where device.auth_user_id = device_auth_user_id
    and device.disconnected_at is null
    and profile.deleted_at is null
    and family.deleted_at is null;

  if not found then
    raise exception 'device is not actively paired' using errcode = '42501';
  end if;

  return pg_catalog.jsonb_build_object(
    'accepted_event_ids', accepted_ids,
    'already_present_event_ids', already_present_ids,
    'server_cursor', authoritative_cursor::text
  );
end;
$$;

comment on function public.ingest_learning_event_batch_for_service(uuid, jsonb) is
  'Service-only atomic LearningEventV1 ingestion response with ordered dispositions and an authoritative device cursor.';

revoke all on function public.claim_device_pairing_for_service(bytea, uuid, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.ingest_learning_event_batch_for_service(uuid, jsonb)
from public, anon, authenticated, service_role;

grant execute on function public.claim_device_pairing_for_service(bytea, uuid, text, text)
to service_role;
grant execute on function public.ingest_learning_event_batch_for_service(uuid, jsonb)
to service_role;
