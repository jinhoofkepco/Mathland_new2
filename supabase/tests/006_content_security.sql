begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000061', '{"role":"editor"}'),
  ('00000000-0000-4000-8000-000000000062', '{"role":"owner"}'),
  ('00000000-0000-4000-8000-000000000063', '{}'),
  ('00000000-0000-4000-8000-000000000064', '{}');

insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values (
  '60000000-0000-4000-8000-000000000061',
  'addition',
  '덧셈 초안',
  '{"activity_id":"addition","content_version":"2.0.0"}',
  '00000000-0000-4000-8000-000000000062',
  '00000000-0000-4000-8000-000000000062'
);

insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000061', 'foundation_ten_rods', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '{"visibility":"retired"}', 1, '00000000-0000-4000-8000-000000000062'
  ),
  (
    '70000000-0000-4000-8000-000000000062', 'foundation_ten_rods', '1.1.0',
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    '{"visibility":"active"}', 1, '00000000-0000-4000-8000-000000000062'
  ),
  (
    '70000000-0000-4000-8000-000000000063', 'foundation_ten_rods', '1.2.0',
    'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    '{"visibility":"future"}', 1, '00000000-0000-4000-8000-000000000062'
  );

insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status, retired_at, retired_by
) values
  (
    '71000000-0000-4000-8000-000000000061', 'foundation_ten_rods', '1.0.0',
    '70000000-0000-4000-8000-000000000061', '00000000-0000-4000-8000-000000000062',
    statement_timestamp() - interval '3 days', statement_timestamp() - interval '3 days',
    'retired', statement_timestamp() - interval '2 days',
    '00000000-0000-4000-8000-000000000062'
  ),
  (
    '71000000-0000-4000-8000-000000000062', 'foundation_ten_rods', '1.1.0',
    '70000000-0000-4000-8000-000000000062', '00000000-0000-4000-8000-000000000062',
    statement_timestamp() - interval '2 days', statement_timestamp() - interval '2 days',
    'active', null, null
  ),
  (
    '71000000-0000-4000-8000-000000000063', 'foundation_ten_rods', '1.2.0',
    '70000000-0000-4000-8000-000000000063', '00000000-0000-4000-8000-000000000062',
    statement_timestamp(), statement_timestamp() + interval '1 day',
    'pending', null, null
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000061', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000061","app_metadata":{"role":"editor"}}',
  true
);

select throws_like(
  $$insert into public.content_versions (
      activity_id, content_version, checksum, package, source_revision, created_by
    ) values (
      'addition', '9.9.9',
      'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      '{}', 1, '00000000-0000-4000-8000-000000000061'
    )$$,
  '%permission denied%',
  'editor cannot directly create a supposedly validated version'
);

select lives_ok(
  $$insert into public.content_drafts (activity_id, title, package)
    values ('subtraction', '뺄셈 초안', '{"activity_id":"subtraction","content_version":"1.0.0"}')$$,
  'editor can create an authored draft without controlling audit columns'
);
select is(
  (select revision from public.content_drafts where activity_id = 'subtraction'),
  1,
  'draft creation forces the initial revision'
);
select is(
  (select created_by from public.content_drafts where activity_id = 'subtraction'),
  '00000000-0000-4000-8000-000000000061'::uuid,
  'draft creation derives its creator from auth.uid'
);
select ok(
  (select created_at >= statement_timestamp() - interval '1 minute'
   from public.content_drafts where activity_id = 'subtraction'),
  'draft creation uses a server timestamp'
);

select throws_like(
  $$update public.content_drafts
    set revision = 99, updated_at = '2001-01-01T00:00:00Z'
    where activity_id = 'subtraction'$$,
  '%permission denied%',
  'editor cannot forge draft revision or update time'
);
select lives_ok(
  $$update public.content_drafts
    set title = '뺄셈 초안 수정', package = '{"activity_id":"subtraction","content_version":"1.0.1"}'
    where activity_id = 'subtraction'$$,
  'editor can update authored draft fields'
);
select is(
  (select revision from public.content_drafts where activity_id = 'subtraction'),
  2,
  'each authored draft update advances revision by exactly one'
);
select is(
  (select updated_by from public.content_drafts where activity_id = 'subtraction'),
  '00000000-0000-4000-8000-000000000061'::uuid,
  'draft update derives its actor from auth.uid'
);
select ok(
  (select updated_at >= statement_timestamp() - interval '1 minute'
   from public.content_drafts where activity_id = 'subtraction'),
  'draft update uses a server timestamp'
);
select throws_like(
  $$update public.content_drafts
    set validation_report = '{"valid":true}',
        validation_checksum = 'sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    where activity_id = 'subtraction'$$,
  '%permission denied%',
  'editor cannot forge server validation evidence'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000062', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000062","app_metadata":{"role":"owner"}}',
  true
);
select throws_like(
  $$insert into public.content_versions (
      activity_id, content_version, checksum, package, source_revision, created_by
    ) values (
      'addition', '9.9.8',
      'sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      '{}', 1, '00000000-0000-4000-8000-000000000062'
    )$$,
  '%permission denied%',
  'owner cannot bypass the server validation boundary for versions'
);
select throws_like(
  $$insert into public.content_publications (
      activity_id, content_version, version_id, published_by
    ) values (
      'foundation_ten_rods', '1.0.0', '70000000-0000-4000-8000-000000000061',
      '00000000-0000-4000-8000-000000000062'
    )$$,
  '%permission denied%',
  'owner cannot bypass the server publication workflow'
);
select throws_like(
  $$update public.content_publications
    set status = 'retired', retired_at = statement_timestamp(),
        retired_by = '00000000-0000-4000-8000-000000000062'
    where id = '71000000-0000-4000-8000-000000000062'$$,
  '%permission denied%',
  'owner cannot directly mutate publication history'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000064', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000064","is_anonymous":true,"app_metadata":{}}',
  true
);
select throws_like(
  $$select id from public.content_versions$$,
  '%permission denied%',
  'device cannot read immutable version history directly'
);
select throws_like(
  $$select id from public.content_publications$$,
  '%permission denied%',
  'device cannot read publication history directly'
);
select results_eq(
  $$select activity_id, content_version, checksum, package
    from public.get_active_content_packages()$$,
  $$values (
    'foundation_ten_rods'::text,
    '1.1.0'::text,
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'::text,
    '{"visibility":"active"}'::jsonb
  )$$,
  'device RPC exposes only the currently effective active package'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000063', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000063","app_metadata":{}}',
  true
);
select throws_like(
  $$select id from public.content_versions$$,
  '%permission denied%',
  'guardian has no direct content version history privilege'
);
select throws_like(
  $$select id from public.content_publications$$,
  '%permission denied%',
  'guardian has no direct publication history privilege'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000061', 1,
      '{"activity_id":"addition","content_version":"2.0.0","checksum":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb,
      'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000062', statement_timestamp(),
      '81000000-0000-4000-8000-000000000061', null
    )$$,
  '%permission denied%',
  'authenticated clients cannot execute the privileged publication transaction'
);

reset role;
set local role service_role;
select lives_ok(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000061', 1,
      '{"activity_id":"addition","content_version":"2.0.0","checksum":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb,
      'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000062', statement_timestamp(),
      '81000000-0000-4000-8000-000000000061', null
    )$$,
  'service role commits validated version, pointer, and audit in one transaction'
);
reset role;

select is(
  (select count(*) from public.content_versions
   where activity_id = 'addition' and content_version = '2.0.0'),
  1::bigint,
  'service publication creates one immutable version'
);
select is(
  (select count(*) from public.content_publications publication
   join public.content_versions version on version.id = publication.version_id
   where publication.activity_id = 'addition'
     and publication.status = 'active'
     and version.checksum = 'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'),
  1::bigint,
  'service publication atomically advances the active pointer'
);
select is(
  (select count(*) from public.audit_log
   where action = 'content_published'
     and request_id = '81000000-0000-4000-8000-000000000061'),
  1::bigint,
  'service publication atomically appends its audit fact'
);

set local role service_role;
select throws_like(
  $$update public.content_drafts
    set activity_id = 'multiplication', created_at = statement_timestamp()
    where id = '60000000-0000-4000-8000-000000000061'$$,
  '%identity is immutable%',
  'draft identity remains immutable even for privileged workflows'
);
reset role;

select * from finish();
rollback;
