create extension if not exists pgcrypto with schema extensions;

create table public.families (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (deleted_at is null or deleted_at >= created_at)
);

create table public.family_memberships (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('guardian', 'editor', 'owner')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint family_memberships_family_user_key unique (family_id, user_id),
  check ((is_active and revoked_at is null) or (not is_active and revoked_at is not null))
);

create index family_memberships_user_active_idx
  on public.family_memberships (user_id, family_id)
  where is_active;

create table public.child_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  client_profile_id text not null check (char_length(client_profile_id) between 1 and 128),
  nickname text not null check (char_length(btrim(nickname)) between 1 and 32),
  birth_year smallint check (birth_year between 2000 and 2100),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint child_profiles_family_client_key unique (family_id, client_profile_id),
  check (deleted_at is null or deleted_at >= created_at)
);

create unique index child_profiles_active_nickname_idx
  on public.child_profiles (family_id, lower(nickname))
  where deleted_at is null;

create table public.devices (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.child_profiles(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 1 and 128),
  profile_local_id text not null check (char_length(profile_local_id) between 1 and 128),
  display_name text not null default 'MathLand Android' check (char_length(display_name) between 1 and 80),
  platform text not null default 'android' check (platform = 'android'),
  last_sequence bigint not null default 0 check (last_sequence >= 0),
  paired_at timestamptz not null default now(),
  last_sync_at timestamptz,
  disconnected_at timestamptz,
  constraint devices_auth_user_key unique (auth_user_id),
  constraint devices_device_id_key unique (device_id),
  constraint devices_id_device_id_key unique (id, device_id),
  check (last_sync_at is null or last_sync_at >= paired_at),
  check (disconnected_at is null or disconnected_at >= paired_at)
);

create index devices_family_profile_idx on public.devices (family_id, profile_id);

create table public.pairing_codes (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.child_profiles(id) on delete cascade,
  code_digest bytea not null check (octet_length(code_digest) = 32),
  created_by uuid not null references auth.users(id) on delete cascade,
  attempt_count smallint not null default 0 check (attempt_count between 0 and 10),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  check (expires_at > created_at),
  check (consumed_at is null or consumed_at >= created_at)
);

create index pairing_codes_profile_lookup_idx
  on public.pairing_codes (profile_id, expires_at desc)
  where consumed_at is null;

comment on table public.pairing_codes is
  'Short-lived device pairing challenges. Only HMAC-SHA256 digests are stored.';
comment on column public.child_profiles.birth_year is
  'Optional coarse age context; exact birth dates are intentionally not collected.';
