begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select no_plan();

insert into auth.users (id, raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000151', '{}'),
  ('00000000-0000-4000-8000-000000000152', '{}'),
  ('00000000-0000-4000-8000-000000000153', '{}'),
  ('00000000-0000-4000-8000-000000000154', '{"role":"owner"}'),
  ('00000000-0000-4000-8000-000000000155', '{"role":"editor"}');

insert into public.families (id, name, created_by) values
  (
    '10000000-0000-4000-8000-000000000151',
    'Studio hardening family',
    '00000000-0000-4000-8000-000000000151'
  );

insert into public.family_memberships (id, family_id, user_id, role) values
  (
    '11000000-0000-4000-8000-000000000151',
    '10000000-0000-4000-8000-000000000151',
    '00000000-0000-4000-8000-000000000151',
    'owner'
  ),
  (
    '11000000-0000-4000-8000-000000000152',
    '10000000-0000-4000-8000-000000000151',
    '00000000-0000-4000-8000-000000000152',
    'editor'
  ),
  (
    '11000000-0000-4000-8000-000000000153',
    '10000000-0000-4000-8000-000000000151',
    '00000000-0000-4000-8000-000000000153',
    'guardian'
  );

insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values (
  '60000000-0000-4000-8000-000000000151',
  'studio_hardening',
  'Studio hardening draft',
  '{"activity_id":"studio_hardening","content_version":"1.0.0"}',
  '00000000-0000-4000-8000-000000000154',
  '00000000-0000-4000-8000-000000000154'
);

insert into public.audit_log (
  id, actor_id, action, target_type, target_id
) values (
  '80000000-0000-4000-8000-000000000151',
  '00000000-0000-4000-8000-000000000154',
  'content_hardening_test',
  'content_draft',
  '60000000-0000-4000-8000-000000000151'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000151',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000151","app_metadata":{}}',
  true
);

select is(
  public.has_global_studio_role('owner'),
  false,
  'family owner is not a global Studio owner'
);
select is(
  (select count(*) from public.content_drafts),
  0::bigint,
  'family owner cannot read global drafts'
);
select is(
  (select count(*) from public.audit_log where family_id is null),
  0::bigint,
  'family owner cannot read global audit facts'
);
select throws_like(
  $$select * from public.get_content_publication_history(null)$$,
  '%owner role is required%',
  'family owner cannot read global publication history'
);
select results_eq(
  $$delete from public.family_memberships
      where id = '11000000-0000-4000-8000-000000000152'
      returning id$$,
  array[]::uuid[],
  'family owner cannot use a global owner branch to delete an editor membership'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000152',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000152","app_metadata":{}}',
  true
);
select is(
  public.has_global_studio_role('editor'),
  false,
  'family editor is not a global Studio editor'
);
select is(
  (select count(*) from public.content_drafts),
  0::bigint,
  'family editor cannot read global drafts'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000154',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000154","app_metadata":{"role":"owner"}}',
  true
);
select is(
  public.has_global_studio_role('owner'),
  true,
  'global owner app metadata authorizes Studio owner access'
);
select is(
  (select count(*) from public.content_drafts),
  1::bigint,
  'global owner can read drafts'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000155',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000155","app_metadata":{"role":"editor"}}',
  true
);
select is(
  public.has_global_studio_role('editor'),
  true,
  'global editor app metadata authorizes Studio editor access'
);
select is(
  (select count(*) from public.content_drafts),
  1::bigint,
  'global editor can read drafts'
);

reset role;

set local role service_role;
create temporary table immediate_publication_result as
select *
from public.commit_validated_content_publication_v2(
  '60000000-0000-4000-8000-000000000151',
  1,
  '{"activity_id":"studio_hardening","content_version":"1.0.0","checksum":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb,
  'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  '{"valid":true,"issues":[],"samples":[]}'::jsonb,
  '00000000-0000-4000-8000-000000000154',
  statement_timestamp() - interval '5 minutes',
  '81000000-0000-4000-8000-000000000151',
  '지연된 즉시 배포',
  null
);
select is(
  (
    select effective_at = published_at and status = 'active'
    from immediate_publication_result
  ),
  true,
  'past client time is replaced by one authoritative database timestamp'
);
reset role;

update public.content_drafts
set package = '{"activity_id":"studio_hardening","content_version":"2.0.0"}'::jsonb,
    revision = revision + 1
where id = '60000000-0000-4000-8000-000000000151';
select set_config(
  'test.future_effective_at',
  (statement_timestamp() + interval '1 day')::text,
  true
);

set local role service_role;
create temporary table future_publication_result as
select *
from public.commit_validated_content_publication_v2(
  '60000000-0000-4000-8000-000000000151',
  2,
  '{"activity_id":"studio_hardening","content_version":"2.0.0","checksum":"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}'::jsonb,
  'sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  '{"valid":true,"issues":[],"samples":[]}'::jsonb,
  '00000000-0000-4000-8000-000000000154',
  current_setting('test.future_effective_at')::timestamptz,
  '81000000-0000-4000-8000-000000000152',
  '미래 수업 예약',
  null
);
select is(
  (
    select effective_at = current_setting('test.future_effective_at')::timestamptz
      and effective_at > published_at
      and status = 'pending'
    from future_publication_result
  ),
  true,
  'genuinely future effective time is preserved and remains pending'
);
reset role;

update public.content_publications
set effective_at = statement_timestamp()
where id = (select publication_id from future_publication_result);

set local role service_role;
select lives_ok(
  format(
    'select public.activate_due_content_publication(%L, %L)',
    (select publication_id from future_publication_result),
    '82000000-0000-4000-8000-000000000151'
  ),
  'the future publication can be activated through the trusted lifecycle RPC'
);
create temporary table rollback_publication_result as
select *
from public.commit_validated_content_publication_v2(
  '60000000-0000-4000-8000-000000000151',
  2,
  '{"activity_id":"studio_hardening","content_version":"1.0.0","checksum":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}'::jsonb,
  'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  '{"valid":true,"issues":[],"samples":[]}'::jsonb,
  '00000000-0000-4000-8000-000000000154',
  statement_timestamp() + interval '1 day',
  '81000000-0000-4000-8000-000000000153',
  'DB 시각으로 즉시 롤백',
  (select publication_id from immediate_publication_result)
);
select is(
  (
    select effective_at = published_at and status = 'active'
    from rollback_publication_result
  ),
  true,
  'rollback ignores a future caller time and commits at database time'
);
reset role;

select * from finish();
rollback;
