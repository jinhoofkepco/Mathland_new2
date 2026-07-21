begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated;
grant execute on all functions in schema extensions to authenticated;
select no_plan();

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000011'),
  ('00000000-0000-4000-8000-000000000012');
insert into public.families (id, name, created_by) values
  ('10000000-0000-4000-8000-000000000001', '가족 A', '00000000-0000-4000-8000-000000000001');
insert into public.family_memberships (family_id, user_id, role) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'guardian');
insert into public.child_profiles (id, family_id, client_profile_id, nickname, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'profile-a', '서아', '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'profile-b', '도윤', '00000000-0000-4000-8000-000000000001');
insert into public.devices (id, family_id, profile_id, auth_user_id, device_id, profile_local_id) values
  ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000011', 'device-a', 'profile-a'),
  ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000012', 'device-b', 'profile-b');
insert into public.guardian_rewards (id, family_id, profile_id, title, created_by) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '공원 가기', '00000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', '책 고르기', '00000000-0000-4000-8000-000000000001');
insert into public.progress_snapshots (id, family_id, profile_id, device_id, through_sequence, snapshot) values
  ('41000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 0, '{}'),
  ('41000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', 0, '{}');
insert into public.reward_inventory (id, family_id, profile_id, reward_id, quantity) values
  ('42000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'apple', 3),
  ('42000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'apple', 7);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000011', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000011","is_anonymous":true,"app_metadata":{}}', true);

select results_eq(
  $$select id from public.devices order by id$$,
  array['30000000-0000-4000-8000-000000000001'::uuid],
  'device sees only its binding'
);
select results_eq(
  $$select id from public.get_device_guardian_rewards() order by id$$,
  array['40000000-0000-4000-8000-000000000001'::uuid],
  'device reward RPC sees only its profile rewards'
);
select throws_like(
  $$select created_by from public.guardian_rewards$$,
  '%permission denied%',
  'device cannot read guardian auth UUIDs from the reward base table'
);
select throws_like(
  $$select id from public.guardian_rewards$$,
  '%permission denied%',
  'device has no direct reward base-table read path'
);
select throws_like(
  $$select public.create_guardian_reward(
      '20000000-0000-4000-8000-000000000001', '기기 위조 보상', 0
    )$$,
  '%not authorized%',
  'anonymous device cannot create a guardian reward through the mutation RPC'
);
select throws_like(
  $$select public.update_guardian_reward(
      '40000000-0000-4000-8000-000000000001',
      '기기 위조 수정', 0, 'claimed'
    )$$,
  '%not authorized%',
  'anonymous device cannot update a guardian reward through the mutation RPC'
);
select throws_like(
  $$select public.delete_guardian_reward(
      '40000000-0000-4000-8000-000000000001'
    )$$,
  '%not authorized%',
  'anonymous device cannot delete a guardian reward through the mutation RPC'
);
select results_eq(
  $$select id from public.progress_snapshots order by id$$,
  array['41000000-0000-4000-8000-000000000001'::uuid],
  'device sees only its own progress snapshot'
);
select results_eq(
  $$select id from public.reward_inventory order by id$$,
  array['42000000-0000-4000-8000-000000000001'::uuid],
  'device sees only its own earned inventory'
);
select results_eq(
  $$select id from public.family_memberships$$,
  array[]::uuid[],
  'device cannot read guardian identity rows'
);
select results_eq(
  $$select id from public.families$$,
  array[]::uuid[],
  'device cannot read family administration rows'
);
select results_eq(
  $$select id from public.child_profiles$$,
  array[]::uuid[],
  'device cannot read child identity rows'
);
select results_eq(
  $$select id from public.content_drafts$$,
  array[]::uuid[],
  'device cannot read content drafts'
);
select results_eq(
  $$select id from public.audit_log$$,
  array[]::uuid[],
  'device cannot read audit facts'
);
select throws_like(
  $$insert into public.families (name, created_by)
    values ('기기 위조 가족', '00000000-0000-4000-8000-000000000011')$$,
  '%row-level security%',
  'anonymous device identity cannot create a family'
);
select throws_like(
  $$insert into public.audit_log (family_id, actor_id, action, target_type, target_id)
    values ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000011', 'forged', 'device', 'x')$$,
  '%row-level security%',
  'device cannot forge audit facts'
);
select throws_like(
  $$select public.export_family_data('10000000-0000-4000-8000-000000000001')$$,
  '%not authorized%',
  'device cannot export guardian family data'
);
select throws_like(
  $$select public.delete_child_profile('20000000-0000-4000-8000-000000000001', '서아')$$,
  '%not authorized%',
  'device cannot delete its bound child profile'
);
select throws_like(
  $$select public.delete_learning_events_for_profile_internal('20000000-0000-4000-8000-000000000001')$$,
  '%permission denied%',
  'device cannot execute the internal privacy primitive'
);
select throws_like(
  $$insert into public.learning_events (
      event_id, family_id, cloud_profile_id, internal_device_id, profile_id, device_id,
      local_sequence, event_type, client_timestamp, payload
    ) values (
      '50000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      'profile-a', 'device-a', 1, 'collection_unlocked', now(),
      '{"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000001","profile_id":"profile-a","device_id":"device-a","sequence":1,"event_type":"collection_unlocked"}'::jsonb
    )$$,
  '%row-level security%',
  'device cannot bypass the ingestion function'
);

select * from finish();
rollback;
