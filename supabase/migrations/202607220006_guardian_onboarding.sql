create function public.bootstrap_guardian_onboarding(
  family_name text,
  child_nickname text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  onboarding_actor_id uuid := auth.uid();
  normalized_family_name text := pg_catalog.regexp_replace(
    family_name,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  normalized_child_nickname text := pg_catalog.regexp_replace(
    child_nickname,
    '^[[:space:]]+|[[:space:]]+$',
    '',
    'g'
  );
  actor_is_anonymous boolean;
  existing_family_id uuid;
  existing_profile_id uuid;
  new_family_id uuid := extensions.gen_random_uuid();
  new_profile_id uuid := extensions.gen_random_uuid();
begin
  if onboarding_actor_id is null then
    raise exception 'guardian onboarding requires authentication' using errcode = '42501';
  end if;

  select account.is_anonymous
  into actor_is_anonymous
  from auth.users account
  where account.id = onboarding_actor_id;

  if coalesce(actor_is_anonymous, true) then
    raise exception 'anonymous device identities cannot create families' using errcode = '42501';
  end if;

  if normalized_family_name is null
     or pg_catalog.char_length(normalized_family_name) not between 1 and 80 then
    raise exception 'family name must contain between 1 and 80 characters' using errcode = '22023';
  end if;
  if normalized_child_nickname is null
     or pg_catalog.char_length(normalized_child_nickname) not between 1 and 32 then
    raise exception 'child nickname must contain between 1 and 32 characters' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('guardian-onboarding:' || onboarding_actor_id::text, 0)
  );

  select audit.family_id, profile.id
  into existing_family_id, existing_profile_id
  from public.audit_log audit
  join public.families family
    on family.id = audit.family_id
   and family.deleted_at is null
   and family.created_by = onboarding_actor_id
  join public.child_profiles profile
    on profile.family_id = family.id
   and profile.deleted_at is null
   and profile.created_by = onboarding_actor_id
   and profile.id::text = audit.metadata ->> 'profile_id'
  where audit.actor_id = onboarding_actor_id
    and audit.action = 'guardian_onboarding_completed'
    and audit.target_type = 'family'
    and audit.target_id = family.id::text
    and audit.metadata ->> 'profile_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  order by audit.created_at
  limit 1;

  if existing_family_id is not null then
    return pg_catalog.jsonb_build_object(
      'familyId', existing_family_id,
      'profileId', existing_profile_id
    );
  end if;

  if exists (
    select 1
    from public.family_memberships membership
    where membership.user_id = onboarding_actor_id
      and membership.is_active
  ) then
    raise exception 'guardian account is already onboarded' using errcode = '23505';
  end if;

  insert into public.families (id, name, created_by)
  values (new_family_id, normalized_family_name, onboarding_actor_id);

  insert into public.family_memberships (family_id, user_id, role)
  values (new_family_id, onboarding_actor_id, 'guardian');

  insert into public.child_profiles (
    id,
    family_id,
    client_profile_id,
    nickname,
    created_by
  ) values (
    new_profile_id,
    new_family_id,
    'pending:' || extensions.gen_random_uuid()::text,
    normalized_child_nickname,
    onboarding_actor_id
  );

  insert into public.pending_child_profile_bindings (
    profile_id,
    family_id,
    pending_marker
  )
  select
    profile.id,
    profile.family_id,
    profile.client_profile_id
  from public.child_profiles profile
  where profile.id = new_profile_id;

  insert into public.audit_log (
    family_id,
    actor_id,
    action,
    target_type,
    target_id,
    metadata
  ) values (
    new_family_id,
    onboarding_actor_id,
    'guardian_onboarding_completed',
    'family',
    new_family_id::text,
    pg_catalog.jsonb_build_object('profile_id', new_profile_id)
  );

  return pg_catalog.jsonb_build_object(
    'familyId', new_family_id,
    'profileId', new_profile_id
  );
end;
$$;

comment on function public.bootstrap_guardian_onboarding(text, text) is
  'Atomically creates one guardian family and a pending first child; retries return the same pair.';

revoke all on function public.bootstrap_guardian_onboarding(text, text) from public;
revoke all on function public.bootstrap_guardian_onboarding(text, text) from anon;
revoke all on function public.bootstrap_guardian_onboarding(text, text) from service_role;
grant execute on function public.bootstrap_guardian_onboarding(text, text) to authenticated;
