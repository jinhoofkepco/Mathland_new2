begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to service_role;
grant execute on all functions in schema extensions to service_role;
select no_plan();

select has_table(
  'public',
  'pairing_rate_limit_buckets',
  'pairing claims use a bounded persistent limiter instead of caller identity alone'
);
select table_privs_are(
  'public',
  'pairing_rate_limit_buckets',
  'service_role',
  array[]::text[],
  'the Edge service cannot read or mutate private limiter buckets directly'
);
select table_privs_are(
  'public',
  'pairing_rate_limit_buckets',
  'authenticated',
  array[]::text[],
  'authenticated clients cannot read or mutate private limiter buckets'
);
select has_table(
  'public',
  'pending_child_profile_bindings',
  'first pairing requires a private server-provisioned pending binding fact'
);
select table_privs_are(
  'public',
  'pending_child_profile_bindings',
  'service_role',
  array[]::text[],
  'the Edge service cannot forge pending child binding facts directly'
);
select table_privs_are(
  'public',
  'pending_child_profile_bindings',
  'authenticated',
  array[]::text[],
  'guardian clients cannot forge pending child binding facts directly'
);

insert into auth.users (id, raw_app_meta_data, is_anonymous) values
  ('00000000-0000-4000-8000-000000000401', '{}', false),
  ('00000000-0000-4000-8000-000000000402', '{}', true),
  ('00000000-0000-4000-8000-000000000403', '{}', true),
  ('00000000-0000-4000-8000-000000000404', '{}', true),
  ('00000000-0000-4000-8000-000000000405', '{}', true),
  ('00000000-0000-4000-8000-000000000406', '{}', true),
  ('00000000-0000-4000-8000-000000000407', '{}', true),
  ('00000000-0000-4000-8000-000000000408', '{}', true),
  ('00000000-0000-4000-8000-000000000409', '{}', true),
  ('00000000-0000-4000-8000-000000000410', '{}', true),
  ('00000000-0000-4000-8000-000000000411', '{}', true),
  ('00000000-0000-4000-8000-000000000412', '{}', true);

insert into public.families (id, name, created_by) values (
  '10000000-0000-4000-8000-000000000401',
  'Hardened pairing family',
  '00000000-0000-4000-8000-000000000401'
);
insert into public.family_memberships (family_id, user_id, role) values (
  '10000000-0000-4000-8000-000000000401',
  '00000000-0000-4000-8000-000000000401',
  'guardian'
);
insert into public.child_profiles (
  id, family_id, client_profile_id, nickname, created_by
) values
  (
    '20000000-0000-4000-8000-000000000401',
    '10000000-0000-4000-8000-000000000401',
    'local-profile-one', 'Child one',
    '00000000-0000-4000-8000-000000000401'
  ),
  (
    '20000000-0000-4000-8000-000000000402',
    '10000000-0000-4000-8000-000000000401',
    'local-profile-two', 'Child two',
    '00000000-0000-4000-8000-000000000401'
  ),
  (
    '20000000-0000-4000-8000-000000000403',
    '10000000-0000-4000-8000-000000000401',
    'pending:11111111-1111-4111-8111-111111111111', 'Pending child',
    '00000000-0000-4000-8000-000000000401'
  ),
  (
    '20000000-0000-4000-8000-000000000404',
    '10000000-0000-4000-8000-000000000401',
    'server-known-unpaired', 'Non-pending child',
    '00000000-0000-4000-8000-000000000401'
  );

insert into public.pending_child_profile_bindings (
  profile_id, family_id, pending_marker
) values (
  '20000000-0000-4000-8000-000000000403',
  '10000000-0000-4000-8000-000000000401',
  'pending:11111111-1111-4111-8111-111111111111'
);

insert into public.families (id, name, created_by) values (
  '10000000-0000-4000-8000-000000000402',
  'Other pairing family',
  '00000000-0000-4000-8000-000000000401'
);
insert into public.family_memberships (family_id, user_id, role) values (
  '10000000-0000-4000-8000-000000000402',
  '00000000-0000-4000-8000-000000000401',
  'guardian'
);
insert into public.child_profiles (
  id, family_id, client_profile_id, nickname, created_by
) values (
  '20000000-0000-4000-8000-000000000405',
  '10000000-0000-4000-8000-000000000402',
  'local-profile-one', 'Other family child',
  '00000000-0000-4000-8000-000000000401'
);

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000401',
      decode(repeat('a1', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates the challenge used by the hardened claim boundary'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a1', 32), 'hex'),
      '00000000-0000-4000-8000-000000000402',
      'device-one', 'wrong-local-profile', 'Phone',
      decode(repeat('11', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'a matched code for the wrong local profile is generic invalid'
);
reset role;
select is(
  (
    select attempt_count
    from public.pairing_codes
    where code_digest = decode(repeat('a1', 32), 'hex')
  ),
  1::smallint,
  'every matched challenge claim increments its bounded attempt count'
);
set local role service_role;
select results_eq(
  $$select outcome, profile_local_id
    from public.claim_device_pairing_for_service(
      decode(repeat('a1', 32), 'hex'),
      '00000000-0000-4000-8000-000000000402',
      'device-one', 'local-profile-one', 'Phone',
      decode(repeat('11', 32), 'hex')
    )$$,
  $$values ('paired'::text, 'local-profile-one'::text)$$,
  'the explicit local profile identity pairs to the selected cloud child'
);

select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000402',
      decode(repeat('a2', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a second child challenge'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a2', 32), 'hex'),
      '00000000-0000-4000-8000-000000000402',
      'rotated-device-id', 'local-profile-two', 'Phone',
      decode(repeat('12', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'an already-bound device does not reveal that a pairing code matched'
);

create temporary table claim_outcomes (ordinal integer, outcome text) on commit drop;
insert into claim_outcomes (ordinal, outcome)
select candidate.ordinal, claim.outcome
from (
  values
    (1, '00000000-0000-4000-8000-000000000403'::uuid, decode(repeat('b1', 32), 'hex')),
    (2, '00000000-0000-4000-8000-000000000404'::uuid, decode(repeat('b2', 32), 'hex')),
    (3, '00000000-0000-4000-8000-000000000405'::uuid, decode(repeat('b3', 32), 'hex')),
    (4, '00000000-0000-4000-8000-000000000406'::uuid, decode(repeat('b4', 32), 'hex')),
    (5, '00000000-0000-4000-8000-000000000407'::uuid, decode(repeat('b5', 32), 'hex')),
    (6, '00000000-0000-4000-8000-000000000408'::uuid, decode(repeat('b6', 32), 'hex'))
) candidate(ordinal, actor_id, wrong_digest)
cross join lateral public.claim_device_pairing_for_service(
  candidate.wrong_digest,
  candidate.actor_id,
  'rotated-' || candidate.ordinal,
  'local-profile-one',
  'Rotating phone',
  decode(repeat('22', 32), 'hex')
) claim
order by candidate.ordinal;

select results_eq(
  $$select outcome, count(*) from claim_outcomes group by outcome order by outcome$$,
  $$values ('pairing_code_invalid'::text, 5::bigint), ('rate_limited'::text, 1::bigint)$$,
  'one network cannot evade five attempts by rotating auth and device identities'
);
reset role;

select set_config(
  'test.rate_audit_count',
  (select count(*)::text from public.audit_log where action = 'pairing_claim_attempted'),
  true
);
select set_config(
  'test.rate_bucket_count',
  (select count(*)::text from public.pairing_rate_limit_buckets),
  true
);

set local role service_role;
select is(
  (
    select count(*)
    from generate_series(1, 20) attempt
    cross join lateral public.claim_device_pairing_for_service(
      decode(repeat('ff', 32), 'hex'),
      '00000000-0000-4000-8000-000000000408',
      'unbounded-rotation-' || attempt,
      'local-profile-one',
      'Rotating phone',
      decode(repeat('22', 32), 'hex')
    ) claim
    where claim.outcome = 'rate_limited'
  ),
  20::bigint,
  'repeated claims remain rate limited'
);
reset role;
select is(
  (select count(*) from public.audit_log where action = 'pairing_claim_attempted'),
  current_setting('test.rate_audit_count')::bigint,
  'repeated limited claims do not append unbounded audit rows'
);
select is(
  (select count(*) from public.pairing_rate_limit_buckets),
  current_setting('test.rate_bucket_count')::bigint,
  'repeated limited claims do not create unbounded limiter rows'
);

update public.pairing_rate_limit_buckets
set attempt_count = 1000
where scope = 'project';
select set_config(
  'test.project_bucket_count',
  (select count(*)::text from public.pairing_rate_limit_buckets),
  true
);
set local role service_role;
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('ee', 32), 'hex'),
      '00000000-0000-4000-8000-000000000408',
      'new-network-device', 'local-profile-one', 'Phone',
      decode(repeat('33', 32), 'hex')
    )$$,
  $$values ('rate_limited'::text)$$,
  'the project-wide limiter fails closed before allocating attacker-controlled buckets'
);
reset role;
select is(
  (select count(*) from public.pairing_rate_limit_buckets),
  current_setting('test.project_bucket_count')::bigint,
  'a saturated project limiter keeps persistent storage bounded'
);

set local role service_role;
select is(
  public.ingest_learning_event_batch_for_service(
    '00000000-0000-4000-8000-000000000402',
    '[
      {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000401","profile_id":"local-profile-one","device_id":"device-one","sequence":1,"client_timestamp":"2026-07-22T03:00:00Z","event_type":"collection_unlocked","collection_id":"one"}
    ]'::jsonb
  ),
  '{"server_cursor":"1","accepted_event_ids":["50000000-0000-4000-8000-000000000401"],"already_present_event_ids":[]}'::jsonb,
  'the first contiguous event advances the authoritative cursor'
);
select throws_like(
  $$select public.ingest_learning_event_batch_for_service(
      '00000000-0000-4000-8000-000000000402',
      '[
        {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000403","profile_id":"local-profile-one","device_id":"device-one","sequence":3,"client_timestamp":"2026-07-22T03:00:02Z","event_type":"collection_unlocked","collection_id":"three"}
      ]'::jsonb
    )$$,
  '%contiguous%',
  'a new sequence cannot jump over the locked cursor'
);
select is(
  public.ingest_learning_event_batch_for_service(
    '00000000-0000-4000-8000-000000000402',
    '[
      {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000401","profile_id":"local-profile-one","device_id":"device-one","sequence":1,"client_timestamp":"2026-07-22T03:00:00Z","event_type":"collection_unlocked","collection_id":"one"},
      {"contract_version":1,"event_id":"50000000-0000-4000-8000-000000000402","profile_id":"local-profile-one","device_id":"device-one","sequence":2,"client_timestamp":"2026-07-22T03:00:01Z","event_type":"collection_unlocked","collection_id":"two"}
    ]'::jsonb
  ),
  '{"server_cursor":"2","accepted_event_ids":["50000000-0000-4000-8000-000000000402"],"already_present_event_ids":["50000000-0000-4000-8000-000000000401"]}'::jsonb,
  'exact replay stays idempotent while the next contiguous event advances the cursor'
);
reset role;
select is(
  (
    select last_sequence
    from public.devices
    where auth_user_id = '00000000-0000-4000-8000-000000000402'
  ),
  2::bigint,
  'device cursor is the contiguous acknowledged prefix'
);
select is(
  (
    select count(*)
    from public.learning_events
    where event_id = '50000000-0000-4000-8000-000000000403'
  ),
  0::bigint,
  'the rejected gap event is not persisted'
);

-- A reinstalled app can receive a new anonymous Auth identity while retaining
-- its installation identifier. A fresh guardian challenge may rotate only the
-- Auth identity on that exact physical/profile binding.
delete from public.pairing_rate_limit_buckets;
select set_config(
  'test.original_device_id',
  (select id::text from public.devices where device_id = 'device-one'),
  true
);

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000402',
      decode(repeat('a3', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a challenge for a different cloud child'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a3', 32), 'hex'),
      '00000000-0000-4000-8000-000000000409',
      'device-one', 'local-profile-two', 'Reinstalled phone',
      decode(repeat('44', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'a new Auth identity cannot take an existing device into another cloud profile'
);
reset role;
select is(
  (select auth_user_id from public.devices where device_id = 'device-one'),
  '00000000-0000-4000-8000-000000000402'::uuid,
  'a rejected cross-profile refresh preserves the original Auth binding'
);
select ok(
  (
    select consumed_at is null and attempt_count = 1
    from public.pairing_codes
    where code_digest = decode(repeat('a3', 32), 'hex')
  ),
  'a rejected refresh counts the matched attempt without consuming its challenge'
);

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000405',
      decode(repeat('a5', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a challenge for a child in another family'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a5', 32), 'hex'),
      '00000000-0000-4000-8000-000000000409',
      'device-one', 'local-profile-one', 'Cross-family phone',
      decode(repeat('52', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'Auth refresh cannot move an existing device across families'
);
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000401',
      decode(repeat('a6', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a challenge for collision regression checks'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a6', 32), 'hex'),
      '00000000-0000-4000-8000-000000000409',
      'device-one', 'different-local-profile', 'Wrong local phone',
      decode(repeat('53', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'Auth refresh cannot alter the existing local profile identity'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a6', 32), 'hex'),
      '00000000-0000-4000-8000-000000000402',
      'different-device', 'local-profile-one', 'Wrong device',
      decode(repeat('54', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'an already-bound Auth identity cannot move to a different device identifier'
);
reset role;
select results_eq(
  $$select auth_user_id,
      (select count(*) from public.devices all_devices)
    from public.devices
    where device_id = 'device-one'$$,
  $$values ('00000000-0000-4000-8000-000000000402'::uuid, 1::bigint)$$,
  'cross-family, local-ID, and device-ID collisions preserve the sole original binding'
);

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000401',
      decode(repeat('a4', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a fresh challenge for the existing device profile'
);
select results_eq(
  $$select outcome, device_id, family_id, profile_id, profile_local_id
    from public.claim_device_pairing_for_service(
      decode(repeat('a4', 32), 'hex'),
      '00000000-0000-4000-8000-000000000409',
      'device-one', 'local-profile-one', 'Reinstalled phone',
      decode(repeat('45', 32), 'hex')
    )$$,
  $$select
      'paired'::text,
      current_setting('test.original_device_id')::uuid,
      '10000000-0000-4000-8000-000000000401'::uuid,
      '20000000-0000-4000-8000-000000000401'::uuid,
      'local-profile-one'::text$$,
  'a valid guardian challenge rotates Auth on the exact existing device/profile binding'
);
reset role;
select results_eq(
  $$select id, auth_user_id, family_id, profile_id, profile_local_id,
      display_name, last_sequence
    from public.devices
    where device_id = 'device-one'$$,
  $$select
      current_setting('test.original_device_id')::uuid,
      '00000000-0000-4000-8000-000000000409'::uuid,
      '10000000-0000-4000-8000-000000000401'::uuid,
      '20000000-0000-4000-8000-000000000401'::uuid,
      'local-profile-one'::text,
      'Reinstalled phone'::text,
      2::bigint$$,
  're-pair preserves the device row, profile identity, and sync cursor while rotating Auth'
);
select ok(
  (
    select consumed_at is not null
      and consumed_by = '00000000-0000-4000-8000-000000000409'::uuid
      and attempt_count = 1
    from public.pairing_codes
    where code_digest = decode(repeat('a4', 32), 'hex')
  ),
  'the successful re-pair consumes the guardian challenge atomically'
);

set local role service_role;
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a4', 32), 'hex'),
      '00000000-0000-4000-8000-000000000410',
      'device-one', 'local-profile-one', 'Replay phone',
      decode(repeat('46', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'a consumed guardian challenge cannot rotate the device Auth identity again'
);
reset role;
select is(
  (select auth_user_id from public.devices where device_id = 'device-one'),
  '00000000-0000-4000-8000-000000000409'::uuid,
  'a consumed-code replay leaves the refreshed Auth binding unchanged'
);

set local role service_role;
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000403',
      decode(repeat('a8', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a challenge for a server-provisioned pending child'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a8', 32), 'hex'),
      '00000000-0000-4000-8000-000000000411',
      'first-device',
      'pending:22222222-2222-4222-8222-222222222222',
      'First phone', decode(repeat('47', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'a device cannot submit a value from the server-reserved pending namespace'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a8', 32), 'hex'),
      '00000000-0000-4000-8000-000000000411',
      'first-device', 'local-profile-one',
      'First phone', decode(repeat('47', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'first bind cannot adopt a local ID already owned by another child in the family'
);
reset role;
select results_eq(
  $$select client_profile_id,
      (select count(*) from public.devices device where device.profile_id = profile.id)
    from public.child_profiles profile
    where profile.id = '20000000-0000-4000-8000-000000000403'$$,
  $$values (
      'pending:11111111-1111-4111-8111-111111111111'::text,
      0::bigint
    )$$,
  'rejected first-bind attempts preserve the pending marker and create no device'
);

set local role service_role;
select results_eq(
  $$select outcome, family_id, profile_id, profile_local_id
    from public.claim_device_pairing_for_service(
      decode(repeat('a8', 32), 'hex'),
      '00000000-0000-4000-8000-000000000411',
      'first-device', 'fresh-local-profile',
      'First phone', decode(repeat('47', 32), 'hex')
    )$$,
  $$values (
      'paired'::text,
      '10000000-0000-4000-8000-000000000401'::uuid,
      '20000000-0000-4000-8000-000000000403'::uuid,
      'fresh-local-profile'::text
    )$$,
  'valid guardian code atomically adopts the first device local profile ID'
);
reset role;
select results_eq(
  $$select profile.client_profile_id, device.profile_local_id, device.auth_user_id
    from public.child_profiles profile
    join public.devices device
      on device.profile_id = profile.id and device.family_id = profile.family_id
    where profile.id = '20000000-0000-4000-8000-000000000403'$$,
  $$values (
      'fresh-local-profile'::text,
      'fresh-local-profile'::text,
      '00000000-0000-4000-8000-000000000411'::uuid
    )$$,
  'first bind stores one consistent cloud/device/local profile identity'
);
select is(
  (
    select count(*)
    from public.pending_child_profile_bindings
    where profile_id = '20000000-0000-4000-8000-000000000403'
  ),
  0::bigint,
  'successful first bind consumes the private pending fact'
);
select ok(
  (
    select consumed_at is not null
      and consumed_by = '00000000-0000-4000-8000-000000000411'::uuid
      and attempt_count = 3
    from public.pairing_codes
    where code_digest = decode(repeat('a8', 32), 'hex')
  ),
  'first bind counts matched attempts and consumes the guardian challenge only on success'
);

set local role service_role;
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a8', 32), 'hex'),
      '00000000-0000-4000-8000-000000000412',
      'first-device', 'fresh-local-profile',
      'Replay first phone', decode(repeat('50', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'a consumed first-bind challenge cannot transfer the device identity'
);
select lives_ok(
  $$select public.create_pairing_challenge_for_service(
      '20000000-0000-4000-8000-000000000404',
      decode(repeat('a9', 32), 'hex'),
      statement_timestamp() + interval '10 minutes',
      '00000000-0000-4000-8000-000000000401'
    )$$,
  'guardian creates a challenge for an unpaired non-pending child'
);
select results_eq(
  $$select outcome from public.claim_device_pairing_for_service(
      decode(repeat('a9', 32), 'hex'),
      '00000000-0000-4000-8000-000000000412',
      'non-pending-device', 'different-local-profile',
      'Other phone', decode(repeat('51', 32), 'hex')
    )$$,
  $$values ('pairing_code_invalid'::text)$$,
  'an ordinary unpaired child cannot silently adopt a different local profile ID'
);
reset role;
select results_eq(
  $$select client_profile_id,
      (select count(*) from public.devices device where device.profile_id = profile.id)
    from public.child_profiles profile
    where profile.id = '20000000-0000-4000-8000-000000000404'$$,
  $$values ('server-known-unpaired'::text, 0::bigint)$$,
  'failed non-pending first bind leaves the cloud child unchanged'
);

select function_privs_are(
  'public',
  'claim_device_pairing_for_service',
  array['bytea', 'uuid', 'text', 'text', 'text', 'bytea'],
  'service_role',
  array['EXECUTE'],
  'service role alone receives the hardened claim signature'
);
select function_privs_are(
  'public',
  'claim_device_pairing_for_service',
  array['bytea', 'uuid', 'text', 'text', 'text', 'bytea'],
  'anon',
  array[]::text[],
  'anonymous SQL role cannot execute the hardened claim directly'
);

select * from finish();
rollback;
