begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated;
grant execute on all functions in schema extensions to authenticated;
select no_plan();

insert into auth.users (id) values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000011');
insert into public.families (id, name, created_by) values
  ('10000000-0000-4000-8000-000000000001', '가족 A', '00000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002', '가족 B', '00000000-0000-4000-8000-000000000002');
insert into public.family_memberships (family_id, user_id, role) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'guardian'),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002', 'guardian');
insert into public.child_profiles (id, family_id, client_profile_id, nickname, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'profile-a', '서아', '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'profile-b', '별이', '00000000-0000-4000-8000-000000000002');
insert into public.devices (id, family_id, profile_id, auth_user_id, device_id, profile_local_id) values
  ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000011', 'device-a', 'profile-a');
insert into public.pairing_codes (id, family_id, profile_id, code_digest, created_by, expires_at) values
  ('31000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', decode(repeat('ab', 32), 'hex'), '00000000-0000-4000-8000-000000000001', now() + interval '10 minutes');
insert into public.learning_events (
  id, event_id, family_id, cloud_profile_id, internal_device_id, profile_id, device_id,
  local_sequence, event_type, client_timestamp, payload
) values (
  '50000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000011',
  '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001', 'profile-a', 'device-a', 1,
  'collection_unlocked', '2026-07-21T09:00:00Z',
  '{"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000011","profile_id":"profile-a","device_id":"device-a","sequence":1,"client_timestamp":"2026-07-21T09:00:00Z","event_type":"collection_unlocked","collection_id":"first-shell"}'::jsonb
);
insert into public.progress_snapshots (id, family_id, profile_id, device_id, through_sequence, snapshot) values
  ('41000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 1, '{}');
insert into public.reward_inventory (id, family_id, profile_id, reward_id, quantity) values
  ('42000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'apple', 3);
insert into public.guardian_rewards (id, family_id, profile_id, title, created_by) values
  ('43000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '공원 가기', '00000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","app_metadata":{}}', true);

select throws_like(
  $$select public.export_family_data('10000000-0000-4000-8000-000000000002')$$,
  '%not authorized%',
  'guardian cannot export another family'
);
select is(
  public.export_family_data('10000000-0000-4000-8000-000000000001') -> 'family' ->> 'id',
  '10000000-0000-4000-8000-000000000001',
  'guardian can export their family'
);
select throws_like(
  $$select public.delete_child_profile('20000000-0000-4000-8000-000000000002', '별이')$$,
  '%not authorized%',
  'guardian cannot delete another family profile'
);
select throws_like(
  $$select public.delete_child_profile('20000000-0000-4000-8000-000000000001', '틀림')$$,
  '%confirmation%',
  'profile deletion requires exact nickname confirmation'
);
select lives_ok(
  $$select public.delete_child_profile('20000000-0000-4000-8000-000000000001', '서아')$$,
  'guardian can delete their confirmed profile'
);

reset role;
select is(
  (select count(*) from public.child_profiles where id = '20000000-0000-4000-8000-000000000001'),
  0::bigint,
  'profile row is removed'
);
select is(
  (
    select count(*)
    from (
      select profile_id from public.devices where profile_id = '20000000-0000-4000-8000-000000000001'
      union all
      select profile_id from public.pairing_codes where profile_id = '20000000-0000-4000-8000-000000000001'
      union all
      select cloud_profile_id from public.learning_events where cloud_profile_id = '20000000-0000-4000-8000-000000000001'
      union all
      select profile_id from public.progress_snapshots where profile_id = '20000000-0000-4000-8000-000000000001'
      union all
      select profile_id from public.reward_inventory where profile_id = '20000000-0000-4000-8000-000000000001'
      union all
      select profile_id from public.guardian_rewards where profile_id = '20000000-0000-4000-8000-000000000001'
    ) child_row
  ),
  0::bigint,
  'all profile-linked cloud rows are removed'
);
select is(
  (select count(*) from public.audit_log where action = 'profile_deleted'),
  1::bigint,
  'an anonymized deletion audit fact remains'
);
select ok(
  not exists (
    select 1
    from public.audit_log
    where action = 'profile_deleted'
      and metadata::text like '%서아%'
  ),
  'deletion audit contains no child nickname'
);

select * from finish();
rollback;
