begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select no_plan();

insert into auth.users (id, raw_app_meta_data) values
  ('00000000-0000-4000-8000-000000000131', '{"role":"owner"}'),
  ('00000000-0000-4000-8000-000000000132', '{"role":"editor"}');

insert into public.content_drafts (
  id, activity_id, title, revision, package, created_by, updated_by
) values
  (
    '60000000-0000-4000-8000-000000000131', 'studio_wire_a', 'Studio A', 7,
    '{"activity_id":"studio_wire_a","content_version":"2.0.0"}',
    '00000000-0000-4000-8000-000000000131',
    '00000000-0000-4000-8000-000000000131'
  ),
  (
    '60000000-0000-4000-8000-000000000132', 'studio_wire_b', 'Studio B', 4,
    '{"activity_id":"studio_wire_b","content_version":"1.0.0"}',
    '00000000-0000-4000-8000-000000000131',
    '00000000-0000-4000-8000-000000000131'
  );

insert into public.content_versions (
  id, activity_id, content_version, checksum, package,
  source_draft_id, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000131', 'studio_wire_a', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa131',
    '{"activity_id":"studio_wire_a","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa131"}',
    '60000000-0000-4000-8000-000000000131', 3,
    '00000000-0000-4000-8000-000000000131'
  ),
  (
    '70000000-0000-4000-8000-000000000132', 'studio_wire_b', '1.0.0',
    'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb132',
    '{"activity_id":"studio_wire_b","content_version":"1.0.0","checksum":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb132"}',
    '60000000-0000-4000-8000-000000000132', 4,
    '00000000-0000-4000-8000-000000000131'
  );

insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status, retired_at, retired_by
) values
  (
    '71000000-0000-4000-8000-000000000131', 'studio_wire_a', '1.0.0',
    '70000000-0000-4000-8000-000000000131',
    '00000000-0000-4000-8000-000000000131',
    statement_timestamp() - interval '2 days', statement_timestamp() - interval '2 days',
    'retired', statement_timestamp() - interval '1 day',
    '00000000-0000-4000-8000-000000000131'
  ),
  (
    '71000000-0000-4000-8000-000000000132', 'studio_wire_b', '1.0.0',
    '70000000-0000-4000-8000-000000000132',
    '00000000-0000-4000-8000-000000000131',
    statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day',
    'cancelled', statement_timestamp(),
    '00000000-0000-4000-8000-000000000131'
  );

insert into public.audit_log (
  actor_id, action, target_type, target_id, request_id, metadata
) values (
  '00000000-0000-4000-8000-000000000131',
  'content_published', 'content_publication',
  '71000000-0000-4000-8000-000000000131',
  '81000000-0000-4000-8000-000000000131',
  '{"reason":"Studio wire test","validation_valid":true}'
);

set local role service_role;
select results_eq(
  $$select publication_id, current_draft_id, current_draft_revision
    from public.get_content_publication_for_rollback(
      '71000000-0000-4000-8000-000000000131'
    )$$,
  $$values (
    '71000000-0000-4000-8000-000000000131'::uuid,
    '60000000-0000-4000-8000-000000000131'::uuid,
    7
  )$$,
  'rollback projection carries the current optimistic draft identity'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000132', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000132","app_metadata":{"role":"editor"}}',
  true
);
select throws_like(
  $$select * from public.get_content_publication_history(null)$$,
  '%owner role is required%',
  'editor cannot use the all-activity history projection'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000131', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000131","app_metadata":{"role":"owner"}}',
  true
);
select results_eq(
  $$select activity_id, source_revision, status, validation_valid
    from public.get_content_publication_history(null)$$,
  $$values ('studio_wire_a'::text, 3, 'retired'::text, true)$$,
  'owner all-activity history is wire-complete and omits cancelled schedules'
);
select results_eq(
  $$select activity_id, source_revision
    from public.get_content_publication_history('studio_wire_a')$$,
  $$values ('studio_wire_a'::text, 3)$$,
  'owner can still scope publication history to one activity'
);
reset role;

select * from finish();
rollback;
