create function public.is_family_member(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_memberships membership
    where membership.family_id = target_family_id
      and membership.user_id = auth.uid()
      and membership.is_active
  );
$$;

create function public.is_family_guardian(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_memberships membership
    where membership.family_id = target_family_id
      and membership.user_id = auth.uid()
      and membership.is_active
      and membership.role in ('guardian', 'owner')
  );
$$;

create function public.has_role(required_role text)
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
      where membership.user_id = auth.uid()
        and membership.is_active
        and membership.role = required_role
    );
$$;

revoke all on function public.is_family_member(uuid) from public;
revoke all on function public.is_family_guardian(uuid) from public;
revoke all on function public.has_role(text) from public;
grant execute on function public.is_family_member(uuid) to authenticated, service_role;
grant execute on function public.is_family_guardian(uuid) to authenticated, service_role;
grant execute on function public.has_role(text) to authenticated, service_role;

create view public.guardian_session_summary
with (security_invoker = true)
as
select
  event.family_id,
  event.cloud_profile_id as profile_id,
  event.session_id,
  min(event.client_timestamp) as started_at,
  max(event.client_timestamp) as completed_at,
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
group by event.family_id, event.cloud_profile_id, event.session_id;

create view public.guardian_activity_summary
with (security_invoker = true)
as
select
  event.family_id,
  event.cloud_profile_id as profile_id,
  event.activity_id,
  count(*) as answer_count,
  count(*) filter (where (event.payload ->> 'correctness')::boolean) as correct_count,
  avg(event.response_duration_ms)::bigint as average_response_duration_ms,
  max(event.client_timestamp) as last_played_at
from public.learning_events event
where event.event_type = 'answer_submitted'
group by event.family_id, event.cloud_profile_id, event.activity_id;

create view public.guardian_error_patterns
with (security_invoker = true)
as
select
  event.family_id,
  event.cloud_profile_id as profile_id,
  event.activity_id,
  event.payload ->> 'generator_id' as generator_id,
  event.payload ->> 'band_id' as band_id,
  count(*) as incorrect_count,
  max(event.client_timestamp) as last_incorrect_at
from public.learning_events event
where event.event_type = 'answer_submitted'
  and not (event.payload ->> 'correctness')::boolean
group by
  event.family_id,
  event.cloud_profile_id,
  event.activity_id,
  event.payload ->> 'generator_id',
  event.payload ->> 'band_id';

create view public.guardian_reward_summary
with (security_invoker = true)
as
select
  inventory.family_id,
  inventory.profile_id,
  inventory.reward_id,
  inventory.quantity,
  inventory.updated_at
from public.reward_inventory inventory;

comment on view public.guardian_session_summary is
  'Family-scoped learning aggregates; callers must be constrained by RLS on learning_events.';
comment on view public.guardian_activity_summary is
  'Family-scoped activity aggregates with no raw answer payloads.';
