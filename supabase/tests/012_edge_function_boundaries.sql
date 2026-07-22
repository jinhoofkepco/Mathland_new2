begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to service_role;
grant execute on all functions in schema extensions to service_role;
select no_plan();

select has_index(
  'public',
  'audit_log',
  'audit_log_pairing_claim_actor_created_idx',
  'persistent pairing rate-limit lookups use a bounded actor/time index'
);

insert into auth.users (id, raw_app_meta_data, is_anonymous) values
  ('00000000-0000-4000-8000-000000000201', '{}', false),
  ('00000000-0000-4000-8000-000000000202', '{}', true),
  ('00000000-0000-4000-8000-000000000203', '{}', true);
insert into public.families (id, name, created_by) values
  ('10000000-0000-4000-8000-000000000201', 'Edge boundary family', '00000000-0000-4000-8000-000000000201');
insert into public.family_memberships (family_id, user_id, role) values
  ('10000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000201', 'guardian');
insert into public.child_profiles (
  id, family_id, client_profile_id, nickname, created_by
) values
  (
    '20000000-0000-4000-8000-000000000201',
    '10000000-0000-4000-8000-000000000201',
    'edge-profile-one', 'Edge child one',
    '00000000-0000-4000-8000-000000000201'
  ),
  (
    '20000000-0000-4000-8000-000000000202',
    '10000000-0000-4000-8000-000000000201',
    'edge-profile-two', 'Edge child two',
    '00000000-0000-4000-8000-000000000201'
  );

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000201',
      decode(repeat('ab', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000201'
    )$$,
  'guardian creates a challenge for the Edge claim boundary'
);

select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('00', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'first wrong code returns a generic invalid result'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('01', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'second wrong code remains generic'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('02', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'third wrong code remains generic'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('03', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'fourth wrong code remains generic'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('04', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'fifth wrong code remains generic'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('ab', 32), 'hex'),
      '00000000-0000-4000-8000-000000000202',
      'rate-limited-device',
      'edge-profile-one', 'Rate limited device', decode(repeat('10', 32), 'hex')
    )$$,
  $$values ('rate_limited'::text)$$,
  'the sixth claim fails closed even when the code is correct'
);
reset role;
select is(
  (
    select count(*)
    from public.audit_log
    where actor_id = '00000000-0000-4000-8000-000000000202'
      and action = 'pairing_claim_attempted'
  ),
  5::bigint,
  'only bounded admitted attempts are persisted as audit facts'
);
set local role service_role;

select results_eq(
  $$select
      outcome,
      family_id,
      profile_id,
      profile_local_id
    from public.claim_device_pairing_for_service(
      decode(repeat('ab', 32), 'hex'),
      '00000000-0000-4000-8000-000000000203',
      'edge-device',
      'edge-profile-one', 'MathLand Android', decode(repeat('20', 32), 'hex')
    )$$,
  $$values (
    'paired'::text,
    '10000000-0000-4000-8000-000000000201'::uuid,
    '20000000-0000-4000-8000-000000000201'::uuid,
    'edge-profile-one'::text
  )$$,
  'a fresh anonymous identity atomically consumes and binds the challenge'
);

select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000202',
      decode(repeat('cd', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000201'
    )$$,
  'guardian creates a second-profile challenge'
);
select results_eq(
  $$select outcome
    from public.claim_device_pairing_for_service(
      decode(repeat('cd', 32), 'hex'),
      '00000000-0000-4000-8000-000000000203',
      'edge-device-two',
      'edge-profile-two', 'Second profile attempt', decode(repeat('21', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'one anonymous identity cannot bind a second profile or reveal a code match'
);

select is(
  (
    select public.ingest_learning_event_batch_for_service(
      '00000000-0000-4000-8000-000000000203',
      '[
        {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000201","profile_id":"edge-profile-one","device_id":"edge-device","sequence":1,"client_timestamp":"2026-07-22T03:00:00Z","event_type":"collection_unlocked","collection_id":"edge-one"},
        {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000202","profile_id":"edge-profile-one","device_id":"edge-device","sequence":2,"client_timestamp":"2026-07-22T03:00:01Z","event_type":"collection_unlocked","collection_id":"edge-two"}
      ]'::jsonb
    )
  ),
  '{"server_cursor": "2", "accepted_event_ids": ["50000000-0000-4000-8000-000000000201", "50000000-0000-4000-8000-000000000202"], "already_present_event_ids": []}'::jsonb,
  'ingest wrapper returns ordered accepted IDs and the authoritative cursor'
);
select is(
  (
    select public.ingest_learning_event_batch_for_service(
      '00000000-0000-4000-8000-000000000203',
      '[
        {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000201","profile_id":"edge-profile-one","device_id":"edge-device","sequence":1,"client_timestamp":"2026-07-22T03:00:00Z","event_type":"collection_unlocked","collection_id":"edge-one"},
        {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000202","profile_id":"edge-profile-one","device_id":"edge-device","sequence":2,"client_timestamp":"2026-07-22T03:00:01Z","event_type":"collection_unlocked","collection_id":"edge-two"}
      ]'::jsonb
    )
  ),
  '{"server_cursor": "2", "accepted_event_ids": [], "already_present_event_ids": ["50000000-0000-4000-8000-000000000201", "50000000-0000-4000-8000-000000000202"]}'::jsonb,
  'ingest wrapper classifies an exact replay without duplicating rows'
);

reset role;
select function_privs_are(
  'public',
  'claim_device_pairing_for_service',
  array['bytea', 'uuid', 'text', 'text', 'text', 'bytea'],
  'service_role',
  array['EXECUTE'],
  'service role alone receives the atomic claim boundary'
);
select function_privs_are(
  'public',
  'claim_device_pairing_for_service',
  array['bytea', 'uuid', 'text', 'text', 'text', 'bytea'],
  'anon',
  array[]::text[],
  'anonymous SQL role cannot execute the service boundary directly'
);
select function_privs_are(
  'public',
  'ingest_learning_event_batch_for_service',
  array['uuid', 'jsonb'],
  'service_role',
  array['EXECUTE'],
  'service role alone receives the transactional ingest wrapper'
);
select function_privs_are(
  'public',
  'ingest_learning_event_batch_for_service',
  array['uuid', 'jsonb'],
  'anon',
  array[]::text[],
  'anonymous SQL role cannot execute the ingest wrapper directly'
);

select * from finish();
rollback;
