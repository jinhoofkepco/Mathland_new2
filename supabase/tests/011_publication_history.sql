begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000121', '{"role":"owner"}'),
  ('00000000-0000-4000-8000-000000000122', '{"role":"editor"}');

insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values
  (
    '60000000-0000-4000-8000-000000000121', 'history_publish', 'History publish',
    '{"activity_id":"history_publish","content_version":"1.1.0"}',
    '00000000-0000-4000-8000-000000000121',
    '00000000-0000-4000-8000-000000000121'
  ),
  (
    '60000000-0000-4000-8000-000000000122', 'history_rollback', 'History rollback',
    '{"activity_id":"history_rollback","content_version":"3.0.0"}',
    '00000000-0000-4000-8000-000000000121',
    '00000000-0000-4000-8000-000000000121'
  );

insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000121', 'history_rollback', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa121',
    '{"activity_id":"history_rollback","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa121"}',
    1, '00000000-0000-4000-8000-000000000121'
  ),
  (
    '70000000-0000-4000-8000-000000000122', 'history_rollback', '2.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa122',
    '{"activity_id":"history_rollback","content_version":"2.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa122"}',
    1, '00000000-0000-4000-8000-000000000121'
  );

insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status, retired_at, retired_by
) values
  (
    '71000000-0000-4000-8000-000000000121', 'history_rollback', '1.0.0',
    '70000000-0000-4000-8000-000000000121', '00000000-0000-4000-8000-000000000121',
    statement_timestamp() - interval '2 days', statement_timestamp() - interval '2 days',
    'retired', statement_timestamp() - interval '1 day',
    '00000000-0000-4000-8000-000000000121'
  ),
  (
    '71000000-0000-4000-8000-000000000122', 'history_rollback', '2.0.0',
    '70000000-0000-4000-8000-000000000122', '00000000-0000-4000-8000-000000000121',
    statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day',
    'active', null, null
  );

set local role service_role;
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000121', 1,
      '{"activity_id":"history_publish","content_version":"1.1.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000121', statement_timestamp(),
      '81000000-0000-4000-8000-000000000121', '   ', null
    )$$,
  '%publication reason must contain between 1 and 500 characters%',
  'publication rejects a whitespace-only human reason'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000121', 1,
      '{"activity_id":"history_publish","content_version":"1.1.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000121', statement_timestamp(),
      '81000000-0000-4000-8000-000000000125', E'\n\t\r', null
    )$$,
  '%publication reason must contain between 1 and 500 characters%',
  'publication rejects newline, tab, and carriage-return-only reasons'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000121', 1,
      '{"activity_id":"history_publish","content_version":"1.1.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000121', statement_timestamp(),
      '81000000-0000-4000-8000-000000000122', repeat('가', 501), null
    )$$,
  '%publication reason must contain between 1 and 500 characters%',
  'publication rejects a human reason longer than 500 characters'
);
select lives_ok(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000121', 1,
      '{"activity_id":"history_publish","content_version":"1.1.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb21',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000121', statement_timestamp(),
      '81000000-0000-4000-8000-000000000123', '  새 학기 난이도 조정  ', null
    )$$,
  'normal publication retains a valid human reason atomically'
);
select lives_ok(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000122', 1,
      '{"activity_id":"history_rollback","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa121"}'::jsonb,
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa121',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000121', statement_timestamp(),
      '81000000-0000-4000-8000-000000000124', '현장 오류로 안정 버전 복원',
      '71000000-0000-4000-8000-000000000121'
    )$$,
  'rollback retains a valid human reason atomically'
);
reset role;

select is(
  (select metadata ->> 'reason' from public.audit_log
   where request_id = '81000000-0000-4000-8000-000000000123'),
  '새 학기 난이도 조정',
  'publication audit stores the normalized human reason'
);
select is(
  (select metadata ->> 'reason' from public.audit_log
   where request_id = '81000000-0000-4000-8000-000000000124'),
  '현장 오류로 안정 버전 복원',
  'rollback audit stores the human reason'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000122', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000122","app_metadata":{"role":"editor"}}',
  true
);
select throws_like(
  $$select * from public.get_content_publication_history('history_publish')$$,
  '%owner role is required%',
  'editor cannot read trusted publication history'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000121', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000121","app_metadata":{"role":"owner"}}',
  true
);
select throws_like(
  $$select * from public.content_versions$$,
  '%permission denied%',
  'owner cannot bypass the trusted boundary to read immutable version rows'
);
select throws_like(
  $$select * from public.content_publications$$,
  '%permission denied%',
  'owner cannot bypass the trusted boundary to read publication rows'
);
select results_eq(
  $$select content_version, actor_id, reason, validation_valid
    from public.get_content_publication_history('history_publish')$$,
  $$values (
    '1.1.0'::text,
    '00000000-0000-4000-8000-000000000121'::uuid,
    '새 학기 난이도 조정'::text,
    true
  )$$,
  'owner reads the minimum validated publication history projection'
);
select results_eq(
  $$select content_version, reason, validation_valid, rollback_of_id
    from public.get_content_publication_history('history_rollback')
    where reason is not null$$,
  $$values (
    '1.0.0'::text,
    '현장 오류로 안정 버전 복원'::text,
    true,
    '71000000-0000-4000-8000-000000000121'::uuid
  )$$,
  'owner history exposes the rollback reason without raw table access'
);
reset role;

select * from finish();
rollback;
