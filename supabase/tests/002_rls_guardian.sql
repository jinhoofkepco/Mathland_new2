begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated;
grant execute on all functions in schema extensions to authenticated;
select no_plan();

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002');
insert into public.families (id, name, created_by) values
  ('10000000-0000-4000-8000-000000000001', '가족 A', '00000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002', '가족 B', '00000000-0000-4000-8000-000000000002');
insert into public.family_memberships (family_id, user_id, role) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'guardian'),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'guardian');
insert into public.child_profiles (id, family_id, client_profile_id, nickname, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'profile-a', '서아', '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'profile-b', '별이', '00000000-0000-4000-8000-000000000002');
insert into public.guardian_rewards (id, family_id, profile_id, title, created_by) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '가족 A 보상', '00000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', '가족 B 보상', '00000000-0000-4000-8000-000000000002');
insert into public.reward_inventory (id, family_id, profile_id, reward_id, quantity) values
  ('42000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'apple', 3),
  ('42000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'apple', 7);
insert into public.content_drafts (id, activity_id, title, package, created_by, updated_by) values
  ('60000000-0000-4000-8000-000000000001', 'addition_ones', '비공개 초안', '{}', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001');
insert into public.audit_log (id, family_id, actor_id, action, target_type, target_id) values
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'family_a_fact', 'family', 'a'),
  ('80000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'family_b_fact', 'family', 'b');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","app_metadata":{}}', true);

select results_eq(
  $$select id from public.families order by id$$,
  array['10000000-0000-4000-8000-000000000001'::uuid],
  'guardian reads only their family'
);
select results_eq(
  $$select id from public.child_profiles order by id$$,
  array['20000000-0000-4000-8000-000000000001'::uuid],
  'guardian reads only their child profiles'
);
select results_eq(
  $$select family_id from public.family_memberships order by family_id$$,
  array['10000000-0000-4000-8000-000000000001'::uuid],
  'guardian reads no other-family membership identity'
);
select results_eq(
  $$select id from public.get_guardian_rewards('10000000-0000-4000-8000-000000000001') order by id$$,
  array['40000000-0000-4000-8000-000000000001'::uuid],
  'guardian reward RPC reads only rewards in their family'
);
select results_eq(
  $$select profile_id from public.guardian_reward_summary order by profile_id$$,
  array['20000000-0000-4000-8000-000000000001'::uuid],
  'security-invoker reward view preserves family isolation'
);
select results_eq(
  $$select profile_id from public.guardian_profile_sync_summary order by profile_id$$,
  array['20000000-0000-4000-8000-000000000001'::uuid],
  'security-invoker sync view preserves family isolation'
);
select results_eq(
  $$select id from public.audit_log order by id$$,
  array['80000000-0000-4000-8000-000000000001'::uuid],
  'guardian reads only their family audit facts'
);
select throws_like(
  $$insert into public.child_profiles (family_id, client_profile_id, nickname, created_by)
    values ('10000000-0000-4000-8000-000000000002', 'attack', '침입', '00000000-0000-4000-8000-000000000001')$$,
  '%row-level security%',
  'guardian cannot insert into another family'
);
select is(
  (select count(*) from public.content_drafts),
  0::bigint,
  'guardian has no draft visibility'
);
select results_eq(
  $$update public.child_profiles set nickname = '침입 수정'
    where id = '20000000-0000-4000-8000-000000000002'
    returning id$$,
  array[]::uuid[],
  'guardian cannot update another family profile'
);
select results_eq(
  $$delete from public.family_memberships
    where family_id = '10000000-0000-4000-8000-000000000002'
    returning id$$,
  array[]::uuid[],
  'guardian cannot delete another family membership'
);
select throws_like(
  $$update public.family_memberships set role = 'owner'
    where family_id = '10000000-0000-4000-8000-000000000001'
      and user_id = '00000000-0000-4000-8000-000000000001'$$,
  '%row-level security%',
  'guardian cannot promote their own content role'
);
select lives_ok(
  $$insert into public.families (id, name, created_by)
    values ('10000000-0000-4000-8000-000000000003', '새 가족', '00000000-0000-4000-8000-000000000001')$$,
  'human guardian can create a new family'
);
select lives_ok(
  $$insert into public.family_memberships (family_id, user_id, role)
    values ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', 'guardian')$$,
  'family creator can bootstrap their guardian membership'
);
select throws_like(
  $$insert into public.audit_log (family_id, actor_id, action, target_type, target_id)
    values ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'forged', 'profile', 'x')$$,
  '%row-level security%',
  'guardian cannot forge audit facts'
);

select * from finish();
rollback;
