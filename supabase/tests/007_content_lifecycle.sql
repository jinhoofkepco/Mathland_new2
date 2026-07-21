begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000071', '{"role":"owner"}'),
  ('00000000-0000-4000-8000-000000000072', '{}');

insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values (
  '60000000-0000-4000-8000-000000000071',
  'foundation_ten_rods',
  '현재 10막대 초안',
  '{"activity_id":"foundation_ten_rods","content_version":"3.0.0","marker":"current-draft"}',
  '00000000-0000-4000-8000-000000000071',
  '00000000-0000-4000-8000-000000000071'
);

insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000071', 'foundation_ten_rods', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '{"activity_id":"foundation_ten_rods","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","marker":"rollback"}',
    1, '00000000-0000-4000-8000-000000000071'
  ),
  (
    '70000000-0000-4000-8000-000000000072', 'foundation_ten_rods', '2.0.0',
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    '{"activity_id":"foundation_ten_rods","content_version":"2.0.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","marker":"current"}',
    1, '00000000-0000-4000-8000-000000000071'
  ),
  (
    '70000000-0000-4000-8000-000000000073', 'multiplication', '1.0.0',
    'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    '{"activity_id":"multiplication","content_version":"1.0.0","checksum":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","marker":"active"}',
    1, '00000000-0000-4000-8000-000000000071'
  ),
  (
    '70000000-0000-4000-8000-000000000074', 'multiplication', '1.1.0',
    'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    '{"activity_id":"multiplication","content_version":"1.1.0","checksum":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","marker":"pending"}',
    1, '00000000-0000-4000-8000-000000000071'
  ),
  (
    '70000000-0000-4000-8000-000000000075', 'scheduled_stale', '2.0.0',
    'sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    '{"activity_id":"scheduled_stale","content_version":"2.0.0","checksum":"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","marker":"stale-pending"}',
    1, '00000000-0000-4000-8000-000000000071'
  ),
  (
    '70000000-0000-4000-8000-000000000076', 'scheduled_stale', '3.0.0',
    'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    '{"activity_id":"scheduled_stale","content_version":"3.0.0","checksum":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","marker":"newer-active"}',
    1, '00000000-0000-4000-8000-000000000071'
  );

insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status, retired_at, retired_by
) values
  (
    '71000000-0000-4000-8000-000000000071', 'foundation_ten_rods', '1.0.0',
    '70000000-0000-4000-8000-000000000071', '00000000-0000-4000-8000-000000000071',
    statement_timestamp() - interval '3 days', statement_timestamp() - interval '3 days',
    'retired', statement_timestamp() - interval '2 days',
    '00000000-0000-4000-8000-000000000071'
  ),
  (
    '71000000-0000-4000-8000-000000000072', 'foundation_ten_rods', '2.0.0',
    '70000000-0000-4000-8000-000000000072', '00000000-0000-4000-8000-000000000071',
    statement_timestamp() - interval '2 days', statement_timestamp() - interval '2 days',
    'active', null, null
  ),
  (
    '71000000-0000-4000-8000-000000000073', 'multiplication', '1.0.0',
    '70000000-0000-4000-8000-000000000073', '00000000-0000-4000-8000-000000000071',
    statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day',
    'active', null, null
  ),
  (
    '71000000-0000-4000-8000-000000000074', 'multiplication', '1.1.0',
    '70000000-0000-4000-8000-000000000074', '00000000-0000-4000-8000-000000000071',
    statement_timestamp(), statement_timestamp() + interval '2 seconds',
    'pending', null, null
  ),
  (
    '71000000-0000-4000-8000-000000000075', 'scheduled_stale', '3.0.0',
    '70000000-0000-4000-8000-000000000076', '00000000-0000-4000-8000-000000000071',
    statement_timestamp(), statement_timestamp(),
    'active', null, null
  ),
  (
    '71000000-0000-4000-8000-000000000076', 'scheduled_stale', '2.0.0',
    '70000000-0000-4000-8000-000000000075', '00000000-0000-4000-8000-000000000071',
    statement_timestamp(), statement_timestamp() + interval '2 seconds',
    'pending', null, null
  );

set local role service_role;
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000071', 1,
      '{"activity_id":"multiplication","content_version":"1.0.0","checksum":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","marker":"active"}'::jsonb,
      'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000071', statement_timestamp(),
      '81000000-0000-4000-8000-000000000071', '다른 활동 롤백 시도',
      '71000000-0000-4000-8000-000000000073'
    )$$,
  '%rollback publication identity%',
  'rollback rejects a source publication from another activity'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000071', 1,
      '{"activity_id":"foundation_ten_rods","content_version":"9.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","marker":"rollback"}'::jsonb,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000071', statement_timestamp(),
      '81000000-0000-4000-8000-000000000072', '버전 불일치 롤백 시도',
      '71000000-0000-4000-8000-000000000071'
    )$$,
  '%rollback publication identity%',
  'rollback rejects a mismatched historical content version'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000071', 1,
      '{"activity_id":"foundation_ten_rods","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","marker":"substituted"}'::jsonb,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000071', statement_timestamp(),
      '81000000-0000-4000-8000-000000000073', '변조 패키지 롤백 시도',
      '71000000-0000-4000-8000-000000000071'
    )$$,
  '%rollback publication identity%',
  'rollback rejects substituted package bytes for the historical version'
);
select lives_ok(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000071', 1,
      '{"activity_id":"foundation_ten_rods","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","marker":"rollback"}'::jsonb,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000071', statement_timestamp(),
      '81000000-0000-4000-8000-000000000074', '난이도 문제로 1.0.0 복원',
      '71000000-0000-4000-8000-000000000071'
    )$$,
  'rollback reactivates a validated immutable historical version'
);
reset role;

select is(
  (select count(*) from public.content_versions where activity_id = 'foundation_ten_rods'),
  2::bigint,
  'rollback does not insert a duplicate immutable version'
);
select is(
  (select count(*) from public.content_publications
   where activity_id = 'foundation_ten_rods' and status = 'active'),
  1::bigint,
  'rollback leaves exactly one active publication'
);
select is(
  (select version_id from public.content_publications
   where activity_id = 'foundation_ten_rods' and status = 'active'),
  '70000000-0000-4000-8000-000000000071'::uuid,
  'rollback active pointer references the existing historical version row'
);
select is(
  (select rollback_of_id from public.content_publications
   where activity_id = 'foundation_ten_rods' and status = 'active'),
  '71000000-0000-4000-8000-000000000071'::uuid,
  'rollback publication records the exact historical publication source'
);
select is(
  (select status from public.content_publications
   where id = '71000000-0000-4000-8000-000000000072'),
  'retired',
  'rollback retires the previously active publication atomically'
);
select is(
  (select count(*) from public.audit_log
   where action = 'content_rolled_back'
     and request_id = '81000000-0000-4000-8000-000000000074'),
  1::bigint,
  'rollback appends one atomic audit fact'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000072', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000072","is_anonymous":true,"app_metadata":{}}',
  true
);
select results_eq(
  $$select content_version from public.get_active_content_packages()
    where activity_id = 'multiplication'$$,
  array['1.0.0'::text],
  'device sees the old active package before the pending publication is due'
);
select throws_like(
  $$select public.activate_due_content_publication(
      '71000000-0000-4000-8000-000000000074',
      '82000000-0000-4000-8000-000000000071'
    )$$,
  '%permission denied%',
  'authenticated clients cannot execute scheduled activation'
);
reset role;

set local role service_role;
select throws_like(
  $$select public.activate_due_content_publication(
      '71000000-0000-4000-8000-000000000074',
      '82000000-0000-4000-8000-000000000071'
    )$$,
  '%not due%',
  'service worker cannot activate a publication before effective_at'
);
reset role;

select pg_catalog.pg_sleep(2.1);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000072', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000072","is_anonymous":true,"app_metadata":{}}',
  true
);
select results_eq(
  $$select content_version from public.get_active_content_packages()
    where activity_id = 'multiplication'$$,
  array['1.0.0'::text],
  'time passing alone does not expose an unactivated pending package'
);
reset role;

set local role service_role;
select lives_ok(
  $$select public.activate_due_content_publication(
      '71000000-0000-4000-8000-000000000076',
      '82000000-0000-4000-8000-000000000074'
    )$$,
  'worker safely consumes a stale due publication without downgrading the activity'
);
select lives_ok(
  $$select public.activate_due_content_publication(
      '71000000-0000-4000-8000-000000000074',
      '82000000-0000-4000-8000-000000000072'
    )$$,
  'service worker atomically activates a due pending publication'
);
select lives_ok(
  $$select public.activate_due_content_publication(
      '71000000-0000-4000-8000-000000000074',
      '82000000-0000-4000-8000-000000000073'
    )$$,
  'repeated activation is idempotent'
);
reset role;

select is(
  (select status from public.content_publications
   where id = '71000000-0000-4000-8000-000000000075'),
  'active',
  'stale scheduled activation keeps the newer normal publication active'
);
select is(
  (select status from public.content_publications
   where id = '71000000-0000-4000-8000-000000000076'),
  'cancelled',
  'stale lower scheduled publication is deterministically cancelled'
);
select is(
  (select count(*) from public.audit_log
   where action = 'content_publication_cancelled'
     and target_id = '71000000-0000-4000-8000-000000000076'),
  1::bigint,
  'stale schedule cancellation appends one audit fact'
);

select is(
  (select count(*) from public.content_publications
   where activity_id = 'multiplication' and status = 'active'),
  1::bigint,
  'scheduled activation leaves exactly one active publication'
);
select is(
  (select status from public.content_publications
   where id = '71000000-0000-4000-8000-000000000073'),
  'retired',
  'scheduled activation retires the previous active publication'
);
select is(
  (select status from public.content_publications
   where id = '71000000-0000-4000-8000-000000000074'),
  'active',
  'scheduled activation advances the pending publication in place'
);
select is(
  (select count(*) from public.audit_log
   where action = 'content_publication_activated'
     and target_id = '71000000-0000-4000-8000-000000000074'),
  1::bigint,
  'duplicate activation appends only one audit fact'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000072', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000072","is_anonymous":true,"app_metadata":{}}',
  true
);
select results_eq(
  $$select content_version from public.get_active_content_packages()
    where activity_id = 'multiplication'$$,
  array['1.1.0'::text],
  'device sees only the activated package after the worker transition'
);
reset role;

select * from finish();
rollback;
