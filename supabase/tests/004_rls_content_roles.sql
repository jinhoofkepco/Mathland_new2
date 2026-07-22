begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated;
grant execute on all functions in schema extensions to authenticated;
select no_plan();

insert into auth.users (id, raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000021', '{"role":"editor"}'),
  ('00000000-0000-4000-8000-000000000022', '{"role":"owner"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000021', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000021","app_metadata":{"role":"editor"}}', true);

select lives_ok(
  $$insert into public.content_drafts (
      activity_id, title, package
    ) values (
      'foundation_ten_rods', '10막대', '{}'
    )$$,
  'editor can create a draft without controlling server metadata'
);
select throws_like(
  $$insert into public.content_publications (
      activity_id, content_version, version_id, published_by
    ) values (
      'foundation_ten_rods', '1.0.0', '70000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000021'
    )$$,
  '%permission denied%',
  'editor cannot bypass the server publication workflow'
);

reset role;
insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values (
  '70000000-0000-4000-8000-000000000001', 'foundation_ten_rods', '1.0.0',
  'sha256:0000000000000000000000000000000000000000000000000000000000000000', '{}', 1,
  '00000000-0000-4000-8000-000000000022'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000022', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000022","app_metadata":{"role":"owner"}}', true);
select throws_like(
  $$insert into public.content_publications (
      activity_id, content_version, version_id, published_by
    ) values (
      'foundation_ten_rods', '1.0.0', '70000000-0000-4000-8000-000000000001',
      '00000000-0000-4000-8000-000000000022'
    )$$,
  '%permission denied%',
  'owner must publish through the service-role validation workflow'
);

select * from finish();
rollback;
