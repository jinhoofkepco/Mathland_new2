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
select * from finish();
rollback;
