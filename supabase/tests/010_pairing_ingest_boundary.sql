begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to service_role;
grant execute on all functions in schema extensions to service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000101', '{}'),
  ('00000000-0000-4000-8000-000000000102', '{}');
insert into public.families (id, name, created_by) values
  ('10000000-0000-4000-8000-000000000101', 'Pairing family', '00000000-0000-4000-8000-000000000101');
insert into public.family_memberships (family_id, user_id, role) values
  ('10000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000101', 'guardian');
insert into public.child_profiles (
  id, family_id, client_profile_id, nickname, created_by
) values (
  '20000000-0000-4000-8000-000000000101',
  '10000000-0000-4000-8000-000000000101',
  'profile-pairing', 'Pairing child',
  '00000000-0000-4000-8000-000000000101'
);

set local role service_role;
select throws_like(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000101',
      decode(repeat('ab', 32), 'hex'),
      statement_timestamp() + interval '5 minutes',
      '00000000-0000-4000-8000-000000000102'
    )$$,
  '%not authorized%',
  'pairing creation rejects an actor without guardian membership'
);
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000101',
      decode(repeat('ab', 32), 'hex'),
      statement_timestamp() + interval '5 minutes',
      '00000000-0000-4000-8000-000000000101'
    )$$,
  'pairing service creates a bounded digest-only challenge'
);
select results_eq(
  $$select family_id, profile_id, attempt_count
    from public.get_pairing_challenge_for_service(decode(repeat('ab', 32), 'hex'))$$,
  $$values (
    '10000000-0000-4000-8000-000000000101'::uuid,
    '20000000-0000-4000-8000-000000000101'::uuid,
    0::smallint
  )$$,
  'pairing lookup exposes only its exact active challenge metadata'
);
reset role;
select set_config(
  'test.pairing_id',
  (
    select id::text from public.pairing_codes
    where profile_id = '20000000-0000-4000-8000-000000000101'
  ),
  true
);
set local role service_role;
select lives_ok(
  $$select public.commit_device_pairing_for_service(
      current_setting('test.pairing_id')::uuid,
      '00000000-0000-4000-8000-000000000102',
      'device-pairing',
      'MathLand Android'
    )$$,
  'pairing commit atomically consumes the challenge and binds the device'
);
select throws_like(
  $$select public.commit_device_pairing_for_service(
      current_setting('test.pairing_id')::uuid,
      '00000000-0000-4000-8000-000000000102',
      'device-replay',
      'Replay'
    )$$,
  '%not active%',
  'consumed pairing challenge cannot be replayed'
);

select lives_ok(
  $$select * from public.ingest_learning_events_for_service(
      '00000000-0000-4000-8000-000000000102',
      '[{"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000101","profile_id":"profile-pairing","device_id":"device-pairing","sequence":1,"client_timestamp":"2026-07-22T00:00:00Z","event_type":"collection_unlocked","collection_id":"pairing-proof"}]'::jsonb
    )$$,
  'ingest service accepts a valid event only for the bound device identity'
);
select lives_ok(
  $$select * from public.ingest_learning_events_for_service(
      '00000000-0000-4000-8000-000000000102',
      '[{"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000101","profile_id":"profile-pairing","device_id":"device-pairing","sequence":1,"client_timestamp":"2026-07-22T00:00:00Z","event_type":"collection_unlocked","collection_id":"pairing-proof"}]'::jsonb
    )$$,
  'ingest service acknowledges an exact replay idempotently'
);
select throws_like(
  $$select * from public.ingest_learning_events_for_service(
      '00000000-0000-4000-8000-000000000102',
      '[{"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000102","profile_id":"profile-pairing","device_id":"another-device","sequence":2,"client_timestamp":"2026-07-22T00:00:01Z","event_type":"collection_unlocked","collection_id":"forged"}]'::jsonb
    )$$,
  '%does not match the bound device%',
  'ingest service rejects a forged local device identity'
);
reset role;

select is(
  (select count(*) from public.devices
   where auth_user_id = '00000000-0000-4000-8000-000000000102'),
  1::bigint,
  'pairing boundary creates one device binding'
);
select is(
  (select count(*) from public.pairing_codes
   where consumed_by = '00000000-0000-4000-8000-000000000102'
     and consumed_at is not null),
  1::bigint,
  'pairing boundary consumes one challenge'
);
select is(
  (select count(*) from public.learning_events
   where event_id = '50000000-0000-4000-8000-000000000101'),
  1::bigint,
  'idempotent ingest stores one event row'
);
select is(
  (select last_sequence from public.devices
   where auth_user_id = '00000000-0000-4000-8000-000000000102'),
  1::bigint,
  'ingest boundary advances the bound device cursor'
);

select * from finish();
rollback;
