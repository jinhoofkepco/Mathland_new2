begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to service_role;
grant execute on all functions in schema extensions to service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000091', '{"role":"owner"}');

insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values
  (
    '60000000-0000-4000-8000-000000000091', 'semver_numeric', 'Numeric semver',
    '{"activity_id":"semver_numeric","content_version":"1.10.0"}',
    '00000000-0000-4000-8000-000000000091', '00000000-0000-4000-8000-000000000091'
  ),
  (
    '60000000-0000-4000-8000-000000000092', 'semver_downgrade', 'Downgrade',
    '{"activity_id":"semver_downgrade","content_version":"1.9.0"}',
    '00000000-0000-4000-8000-000000000091', '00000000-0000-4000-8000-000000000091'
  ),
  (
    '60000000-0000-4000-8000-000000000093', 'semver_equal', 'Equal',
    '{"activity_id":"semver_equal","content_version":"3.1.4"}',
    '00000000-0000-4000-8000-000000000091', '00000000-0000-4000-8000-000000000091'
  ),
  (
    '60000000-0000-4000-8000-000000000094', 'semver_oversized', 'Oversized',
    '{"activity_id":"semver_oversized","content_version":"9999999999999999999999999999999999999999.0.0"}',
    '00000000-0000-4000-8000-000000000091', '00000000-0000-4000-8000-000000000091'
  );

insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000091', 'semver_numeric', '1.9.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa91',
    '{}', 1, '00000000-0000-4000-8000-000000000091'
  ),
  (
    '70000000-0000-4000-8000-000000000092', 'semver_downgrade', '2.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa92',
    '{}', 1, '00000000-0000-4000-8000-000000000091'
  ),
  (
    '70000000-0000-4000-8000-000000000093', 'semver_equal', '3.1.4',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa93',
    '{}', 1, '00000000-0000-4000-8000-000000000091'
  ),
  (
    '70000000-0000-4000-8000-000000000094', 'semver_oversized', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa94',
    '{}', 1, '00000000-0000-4000-8000-000000000091'
  );

set local role service_role;
select lives_ok(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000091', 1,
      '{"activity_id":"semver_numeric","content_version":"1.10.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb91"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb91',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000091', statement_timestamp(),
      '81000000-0000-4000-8000-000000000091', '숫자 SemVer 비교 검증', null
    )$$,
  'numeric semver comparison accepts 1.10.0 after 1.9.0'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000092', 1,
      '{"activity_id":"semver_downgrade","content_version":"1.9.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb92"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb92',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000091', statement_timestamp(),
      '81000000-0000-4000-8000-000000000092', '다운그레이드 시도', null
    )$$,
  '%semantic version must strictly increase%',
  'normal publication rejects a semantic version downgrade'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000093', 1,
      '{"activity_id":"semver_equal","content_version":"3.1.4","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb93"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb93',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000091', statement_timestamp(),
      '81000000-0000-4000-8000-000000000093', '동일 버전 시도', null
    )$$,
  '%semantic version must strictly increase%',
  'normal publication rejects an equal semantic version before uniqueness handling'
);
select throws_like(
  $$select public.commit_validated_content_publication(
      '60000000-0000-4000-8000-000000000094', 1,
      '{"activity_id":"semver_oversized","content_version":"9999999999999999999999999999999999999999.0.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb94"}'::jsonb,
      'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb94',
      '{"valid":true,"issues":[],"samples":[]}'::jsonb,
      '00000000-0000-4000-8000-000000000091', statement_timestamp(),
      '81000000-0000-4000-8000-000000000094', '과대 버전 시도', null
    )$$,
  '%semantic version is invalid%',
  'oversized semantic version components fail closed before numeric conversion'
);
reset role;

select is(
  (select count(*) from public.content_versions
   where activity_id = 'semver_numeric' and content_version = '1.10.0'),
  1::bigint,
  'accepted numeric semantic version creates one immutable version'
);
select is(
  (select count(*) from public.content_versions
   where activity_id in ('semver_downgrade', 'semver_equal', 'semver_oversized')),
  3::bigint,
  'rejected normal publications create no immutable versions'
);

select * from finish();
rollback;
