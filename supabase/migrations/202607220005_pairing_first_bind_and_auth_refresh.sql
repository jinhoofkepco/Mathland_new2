-- A cloud child cannot know a Godot-local profile identifier before its first
-- device connects. The guardian onboarding boundary provisions a random
-- pending marker and this private fact in one server-side transaction. Only a
-- valid, unconsumed guardian pairing challenge may replace that marker.

create table public.pending_child_profile_bindings (
  profile_id uuid primary key,
  family_id uuid not null,
  pending_marker text not null unique check (
    pending_marker ~ '^pending:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  constraint pending_child_profile_bindings_profile_fkey
    foreign key (profile_id, family_id, pending_marker)
    references public.child_profiles(id, family_id, client_profile_id)
    on delete cascade
);

alter table public.pending_child_profile_bindings enable row level security;
alter table public.pending_child_profile_bindings force row level security;
revoke all on public.pending_child_profile_bindings
from public, anon, authenticated, service_role;

comment on table public.pending_child_profile_bindings is
  'Private one-time facts created only by the server guardian-onboarding boundary. A pairing claim consumes the fact when it adopts the first Godot-local profile ID.';

create or replace function public.claim_device_pairing_for_service(
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
  pending_binding public.pending_child_profile_bindings%rowtype;
  identity_device public.devices%rowtype;
  identifier_device public.devices%rowtype;
  pending_binding_found boolean := false;
  pending_first_bind boolean := false;
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
  if challenge_digest is null
    or network_fingerprint is null
    or pg_catalog.octet_length(challenge_digest) <> 32
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

  -- The same project lock used by the bounded limiter also serializes pending
  -- marker adoption and Auth refreshes with every other pairing claim.
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
  for update of pairing, profile;

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

  update public.pairing_codes pairing
  set attempt_count = pairing.attempt_count + 1
  where pairing.id = pairing_record.id;

  select pending.*
  into pending_binding
  from public.pending_child_profile_bindings pending
  where pending.profile_id = pairing_record.profile_id
    and pending.family_id = pairing_record.family_id
  for update of pending;
  pending_binding_found := found;

  if pending_binding_found then
    if pending_binding.pending_marker is distinct from pairing_record.client_profile_id
      or pg_catalog.lower(profile_local_identifier) like 'pending:%'
      or exists (
        select 1
        from public.devices device
        where device.family_id = pairing_record.family_id
          and device.profile_id = pairing_record.profile_id
      )
      or exists (
        select 1
        from public.child_profiles other_profile
        where other_profile.family_id = pairing_record.family_id
          and other_profile.id is distinct from pairing_record.profile_id
          and other_profile.client_profile_id = profile_local_identifier
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
    pending_first_bind := true;
  elsif pairing_record.client_profile_id is distinct from profile_local_identifier
    or pg_catalog.lower(profile_local_identifier) like 'pending:%' then
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
    pending_first_bind and (identity_device_found or identifier_device_found)
  ) or (
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
    identifier_device_found and (
      identifier_device.family_id is distinct from pairing_record.family_id
      or identifier_device.profile_id is distinct from pairing_record.profile_id
      or identifier_device.profile_local_id is distinct from profile_local_identifier
    )
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

  if pending_first_bind then
    begin
      delete from public.pending_child_profile_bindings pending
      where pending.profile_id = pairing_record.profile_id
        and pending.family_id = pairing_record.family_id
        and pending.pending_marker = pairing_record.client_profile_id;
      if not found then
        raise exception 'pending child binding disappeared' using errcode = '40001';
      end if;

      update public.child_profiles profile
      set client_profile_id = profile_local_identifier,
          updated_at = server_timestamp
      where profile.id = pairing_record.profile_id
        and profile.family_id = pairing_record.family_id
        and profile.client_profile_id = pairing_record.client_profile_id;
      if not found then
        raise exception 'pending child profile changed' using errcode = '40001';
      end if;
    exception when unique_violation then
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
    end;
  end if;

  if identity_device_found then
    selected_device_id := identity_device.id;
    update public.devices
    set display_name = normalized_display_name,
        disconnected_at = null
    where id = selected_device_id;
  elsif identifier_device_found then
    -- Reinstallation may preserve the installation identifier while Supabase
    -- issues a new anonymous Auth identity. All immutable binding fields were
    -- checked above, so only that credential and presentation state rotate.
    selected_device_id := identifier_device.id;
    update public.devices
    set auth_user_id = device_auth_user_id,
        display_name = normalized_display_name,
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
    pg_catalog.jsonb_build_object(
      'profile_id', pairing_record.profile_id,
      'first_bind', pending_first_bind,
      'auth_refreshed', identifier_device_found
        and identifier_device.auth_user_id is distinct from device_auth_user_id
    ),
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
  'Service-only atomic pairing claim with private first-bind adoption, exact device Auth refresh, generic invalid outcomes, and bounded actor/network/project limits.';

revoke all on function public.claim_device_pairing_for_service(
  bytea, uuid, text, text, text, bytea
) from public, anon, authenticated, service_role;
grant execute on function public.claim_device_pairing_for_service(
  bytea, uuid, text, text, text, bytea
) to service_role;
