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

insert into auth.users (id, raw_app_meta_data, is_anonymous) values
  ('00000000-0000-4000-8000-000000000401', '{}', false),
  ('00000000-0000-4000-8000-000000000402', '{}', true),
  ('00000000-0000-4000-8000-000000000403', '{}', true),
  ('00000000-0000-4000-8000-000000000404', '{}', true),
  ('00000000-0000-4000-8000-000000000405', '{}', true),
  ('00000000-0000-4000-8000-000000000406', '{}', true),
  ('00000000-0000-4000-8000-000000000407', '{}', true),
  ('00000000-0000-4000-8000-000000000408', '{}', true);

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
