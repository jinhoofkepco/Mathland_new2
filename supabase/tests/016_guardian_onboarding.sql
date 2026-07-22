begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated;
grant execute on all functions in schema extensions to authenticated;
select no_plan();

insert into auth.users (id, raw_app_meta_data, is_anonymous) values
  ('00000000-0000-4000-8000-000000000161', '{}', false),
  ('00000000-0000-4000-8000-000000000162', '{}', true),
  ('00000000-0000-4000-8000-000000000163', '{}', false);

insert into public.families (id, name, created_by) values (
  '10000000-0000-4000-8000-000000000163',
  'Existing family',
  '00000000-0000-4000-8000-000000000163'
);
insert into public.family_memberships (family_id, user_id, role) values (
  '10000000-0000-4000-8000-000000000163',
  '00000000-0000-4000-8000-000000000163',
  'editor'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000161', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000161","is_anonymous":false,"app_metadata":{}}',
  true
);

select throws_like(
  $$select public.bootstrap_guardian_onboarding('', '모아')$$,
  '%family name must contain between 1 and 80 characters%',
  'blank family names fail before any row is created'
);
select throws_like(
  $$select public.bootstrap_guardian_onboarding(E'\t\n', '모아')$$,
  '%family name must contain between 1 and 80 characters%',
  'tab and newline only family names are blank'
);
select throws_like(
  $$select public.bootstrap_guardian_onboarding('모아네', E'\n\t')$$,
  '%child nickname must contain between 1 and 32 characters%',
  'tab and newline only child nicknames are blank'
);

select set_config(
  'test.onboarding_result',
  public.bootstrap_guardian_onboarding('  모아네 가족  ', '  모아  ')::text,
  true
);
select is(
  (current_setting('test.onboarding_result')::jsonb ->> 'familyId')::uuid,
  (select id from public.families where created_by = '00000000-0000-4000-8000-000000000161'),
  'onboarding returns its newly created family identifier'
);
select is(
  (current_setting('test.onboarding_result')::jsonb ->> 'profileId')::uuid,
  (select id from public.child_profiles where created_by = '00000000-0000-4000-8000-000000000161'),
  'onboarding returns its newly created child identifier'
);
select is(
  (select name from public.families where created_by = '00000000-0000-4000-8000-000000000161'),
  '모아네 가족',
  'family names are normalized server-side'
);
select is(
  (select nickname from public.child_profiles where created_by = '00000000-0000-4000-8000-000000000161'),
  '모아',
  'child nicknames are normalized server-side'
);
select matches(
  (select client_profile_id from public.child_profiles where created_by = '00000000-0000-4000-8000-000000000161'),
  '^pending:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  'the first child uses a strict server-generated pending marker'
);
reset role;
select is(
  (
    select count(*)
    from public.pending_child_profile_bindings pending
    join public.child_profiles profile
      on profile.id = pending.profile_id
     and profile.family_id = pending.family_id
     and profile.client_profile_id = pending.pending_marker
    where profile.created_by = '00000000-0000-4000-8000-000000000161'
  ),
  1::bigint,
  'onboarding records the private one-time adoption fact'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000161', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000161","is_anonymous":false,"app_metadata":{}}',
  true
);
select is(
  public.bootstrap_guardian_onboarding('ignored retry', 'ignored retry'),
  current_setting('test.onboarding_result')::jsonb,
  'a committed request can be retried without creating another family'
);
reset role;
delete from public.pending_child_profile_bindings
where profile_id = (current_setting('test.onboarding_result')::jsonb ->> 'profileId')::uuid;
update public.child_profiles
set client_profile_id = 'godot-local-profile-after-first-bind'
where id = (current_setting('test.onboarding_result')::jsonb ->> 'profileId')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000161', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000161","is_anonymous":false,"app_metadata":{}}',
  true
);
select is(
  public.bootstrap_guardian_onboarding('post-bind retry', 'post-bind retry'),
  current_setting('test.onboarding_result')::jsonb,
  'a retry after first-bind consumes its pending fact still returns the original pair'
);
select is(
  (select count(*) from public.families where created_by = '00000000-0000-4000-8000-000000000161'),
  1::bigint,
  'idempotent onboarding creates one family'
);
select is(
  (select count(*) from public.child_profiles where created_by = '00000000-0000-4000-8000-000000000161'),
  1::bigint,
  'idempotent onboarding creates one child'
);
select is(
  (select count(*) from public.audit_log where actor_id = '00000000-0000-4000-8000-000000000161' and action = 'guardian_onboarding_completed'),
  1::bigint,
  'idempotent onboarding records one audit fact'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000162', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000162","is_anonymous":true,"app_metadata":{}}',
  true
);
select throws_like(
  $$select public.bootstrap_guardian_onboarding('Forged family', 'Device')$$,
  '%anonymous device identities cannot create families%',
  'anonymous device identities cannot enter guardian onboarding'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000163', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000163","is_anonymous":false,"app_metadata":{}}',
  true
);
select throws_like(
  $$select public.bootstrap_guardian_onboarding('Second family', 'Second child')$$,
  '%already onboarded%',
  'an account with an active membership cannot create another family'
);

reset role;
select function_privs_are(
  'public',
  'bootstrap_guardian_onboarding',
  array['text', 'text'],
  'authenticated',
  array['EXECUTE'],
  'authenticated guardians alone receive the onboarding boundary'
);
select function_privs_are(
  'public',
  'bootstrap_guardian_onboarding',
  array['text', 'text'],
  'anon',
  array[]::text[],
  'the public anonymous SQL role cannot execute onboarding'
);
select function_privs_are(
  'public',
  'bootstrap_guardian_onboarding',
  array['text', 'text'],
  'service_role',
  array[]::text[],
  'the service role cannot impersonate guardian onboarding'
);

select * from finish();
rollback;
