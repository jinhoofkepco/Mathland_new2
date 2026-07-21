create function public.reject_append_only_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only', tg_table_name using errcode = 'P0001';
end;
$$;

revoke all on function public.reject_append_only_mutation() from public;

create table public.learning_events (
  id uuid primary key default extensions.gen_random_uuid(),
  event_id uuid not null,
  family_id uuid not null references public.families(id) on delete cascade,
  cloud_profile_id uuid not null references public.child_profiles(id) on delete cascade,
  internal_device_id uuid not null,
  profile_id text not null check (char_length(profile_id) between 1 and 128),
  device_id text not null check (char_length(device_id) between 1 and 128),
  session_id text check (session_id is null or char_length(session_id) between 1 and 128),
  local_sequence bigint not null check (local_sequence between 1 and 9007199254740991),
  event_type text not null check (
    event_type in (
      'run_started',
      'answer_submitted',
      'run_completed',
      'collection_unlocked',
      'coupon_earned'
    )
  ),
  activity_id text check (activity_id is null or char_length(activity_id) between 1 and 128),
  client_timestamp timestamptz not null,
  response_duration_ms bigint not null default 0 check (response_duration_ms >= 0),
  reward_apples bigint not null default 0 check (reward_apples >= 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  received_at timestamptz not null default now(),
  constraint learning_events_event_id_key unique (event_id),
  constraint learning_events_device_sequence_key unique (device_id, local_sequence),
  constraint learning_events_device_binding_fkey
    foreign key (internal_device_id, device_id)
    references public.devices(id, device_id)
    on delete cascade,
  check ((payload ->> 'contract_version') = '1'),
  check ((payload ->> 'event_id') = event_id::text),
  check ((payload ->> 'profile_id') = profile_id),
  check ((payload ->> 'device_id') = device_id),
  check ((payload ->> 'sequence')::bigint = local_sequence),
  check ((payload ->> 'event_type') = event_type)
);

create index learning_events_family_profile_time_idx
  on public.learning_events (family_id, cloud_profile_id, client_timestamp desc);
create index learning_events_activity_time_idx
  on public.learning_events (family_id, activity_id, client_timestamp desc)
  where activity_id is not null;
create index learning_events_unsynced_sequence_idx
  on public.learning_events (internal_device_id, local_sequence);

create trigger learning_events_append_only
before update or delete on public.learning_events
for each row execute function public.reject_append_only_mutation();

create table public.progress_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.child_profiles(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  through_sequence bigint not null check (through_sequence >= 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint progress_snapshots_profile_device_key unique (profile_id, device_id)
);

create table public.reward_inventory (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.child_profiles(id) on delete cascade,
  reward_id text not null check (char_length(reward_id) between 1 and 128),
  quantity bigint not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  constraint reward_inventory_profile_reward_key unique (profile_id, reward_id)
);

create table public.guardian_rewards (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  profile_id uuid not null references public.child_profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  required_apples bigint not null default 0 check (required_apples >= 0),
  status text not null default 'available' check (status in ('available', 'claimed', 'cancelled')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  check ((status = 'claimed') = (claimed_at is not null))
);

create index guardian_rewards_family_profile_idx
  on public.guardian_rewards (family_id, profile_id, created_at desc);
