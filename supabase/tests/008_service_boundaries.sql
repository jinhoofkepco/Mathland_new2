begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
grant usage on schema extensions to service_role;
grant execute on all functions in schema extensions to service_role;
select no_plan();

insert into auth.users (id, app_metadata) values
  ('00000000-0000-4000-8000-000000000081', '{"role":"owner"}');
insert into public.content_drafts (
  id, activity_id, title, package, created_by, updated_by
) values (
  '60000000-0000-4000-8000-000000000081', 'boundary_activity', 'Boundary draft',
  '{"activity_id":"boundary_activity","content_version":"2.0.0"}',
  '00000000-0000-4000-8000-000000000081',
  '00000000-0000-4000-8000-000000000081'
);
insert into public.content_versions (
  id, activity_id, content_version, checksum, package, source_revision, created_by
) values
  (
    '70000000-0000-4000-8000-000000000081', 'boundary_activity', '1.0.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa81',
    '{"activity_id":"boundary_activity","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa81"}',
    1, '00000000-0000-4000-8000-000000000081'
  ),
  (
    '70000000-0000-4000-8000-000000000082', 'boundary_activity', '1.1.0',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa82',
    '{"activity_id":"boundary_activity","content_version":"1.1.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa82"}',
    1, '00000000-0000-4000-8000-000000000081'
  ),
  (
    '70000000-0000-4000-8000-000000000083', 'boundary_attack', '9.9.9',
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa83',
    '{"activity_id":"boundary_attack","content_version":"9.9.9","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa83"}',
    1, '00000000-0000-4000-8000-000000000081'
  );
insert into public.content_publications (
  id, activity_id, content_version, version_id, published_by,
  published_at, effective_at, status, retired_at, retired_by
) values
  (
    '71000000-0000-4000-8000-000000000081', 'boundary_activity', '1.0.0',
    '70000000-0000-4000-8000-000000000081', '00000000-0000-4000-8000-000000000081',
    statement_timestamp() - interval '2 days', statement_timestamp() - interval '2 days',
    'retired', statement_timestamp() - interval '1 day',
    '00000000-0000-4000-8000-000000000081'
  ),
  (
    '71000000-0000-4000-8000-000000000082', 'boundary_activity', '1.1.0',
    '70000000-0000-4000-8000-000000000082', '00000000-0000-4000-8000-000000000081',
    statement_timestamp() - interval '1 day', statement_timestamp() - interval '1 day',
    'active', null, null
  );

set local role service_role;
select throws_like(
  $$select package from public.content_drafts$$,
  '%permission denied%',
  'service role cannot read raw drafts directly'
);
select throws_like(
  $$select package from public.content_versions$$,
  '%permission denied%',
  'service role cannot read raw immutable versions directly'
);
select throws_like(
  $$insert into public.content_versions (
      activity_id, content_version, checksum, package, source_revision, created_by
    ) values (
      'boundary_attack', '9.9.9',
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa83',
      '{}', 1, '00000000-0000-4000-8000-000000000081'
    )$$,
  '%permission denied%',
  'service role cannot insert an unvalidated immutable version directly'
);
select throws_like(
  $$update public.content_publications
    set status = 'retired', retired_at = statement_timestamp(),
        retired_by = '00000000-0000-4000-8000-000000000081'
    where id = '71000000-0000-4000-8000-000000000082'$$,
  '%permission denied%',
  'service role cannot directly replace the active pointer'
);
select throws_like(
  $$insert into public.content_publications (
      activity_id, content_version, version_id, published_by,
      published_at, effective_at, status
    ) values (
      'boundary_attack', '9.9.9',
      '70000000-0000-4000-8000-000000000083',
      '00000000-0000-4000-8000-000000000081',
      statement_timestamp(), statement_timestamp(), 'active'
    )$$,
  '%permission denied%',
  'service role cannot install an unvalidated active publication directly'
);
select throws_like(
  $$insert into public.audit_log (
      actor_id, action, target_type, target_id
    ) values (
      '00000000-0000-4000-8000-000000000081', 'forged_publish', 'content', 'attack'
    )$$,
  '%permission denied%',
  'service role cannot forge a publication audit fact directly'
);
select results_eq(
  $$select id, activity_id, revision, package
    from public.get_content_draft_for_validation('60000000-0000-4000-8000-000000000081')$$,
  $$values (
    '60000000-0000-4000-8000-000000000081'::uuid,
    'boundary_activity'::text,
    1,
    '{"activity_id":"boundary_activity","content_version":"2.0.0"}'::jsonb
  )$$,
  'service validator reads one exact draft through its RPC'
);
select results_eq(
  $$select publication_id, activity_id, content_version, version_id, checksum, package
    from public.get_content_publication_for_rollback('71000000-0000-4000-8000-000000000081')$$,
  $$values (
    '71000000-0000-4000-8000-000000000081'::uuid,
    'boundary_activity'::text,
    '1.0.0'::text,
    '70000000-0000-4000-8000-000000000081'::uuid,
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa81'::text,
    '{"activity_id":"boundary_activity","content_version":"1.0.0","checksum":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa81"}'::jsonb
  )$$,
  'rollback handler reads one exact retired publication through its RPC'
);
reset role;

select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and pg_catalog.has_function_privilege('service_role', procedure.oid, 'execute')
  ),
  9::bigint,
  'service role receives all nine required exact RPCs'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and pg_catalog.has_function_privilege('service_role', procedure.oid, 'execute')
      and procedure.proname not in (
        'activate_due_content_publication',
        'commit_validated_content_publication',
        'commit_device_pairing_for_service',
        'create_pairing_challenge_for_service',
        'get_content_draft_for_validation',
        'get_content_publication_for_rollback',
        'get_due_content_publication_ids',
        'get_pairing_challenge_for_service',
        'ingest_learning_events_for_service'
      )
  ),
  0::bigint,
  'service role executes only the nine exact lifecycle, pairing, and ingest RPCs'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and pg_catalog.has_function_privilege('service_role', procedure.oid, 'execute')
      and (
        procedure.prosecdef is not true
        or procedure.proconfig is distinct from array['search_path=""']::text[]
      )
  ),
  0::bigint,
  'every service RPC is SECURITY DEFINER with an empty search path'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and pg_catalog.has_function_privilege('service_role', procedure.oid, 'execute')
      and (
        pg_catalog.has_function_privilege('anon', procedure.oid, 'execute')
        or pg_catalog.has_function_privilege('authenticated', procedure.oid, 'execute')
      )
  ),
  0::bigint,
  'anon and authenticated roles cannot execute a service-only RPC'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and pg_catalog.has_function_privilege('service_role', procedure.oid, 'execute')
      and exists (
        select 1
        from pg_catalog.aclexplode(
          coalesce(
            procedure.proacl,
            pg_catalog.acldefault('f', procedure.proowner)
          )
        ) privilege
        where privilege.grantee = 0
          and pg_catalog.upper(privilege.privilege_type) = 'EXECUTE'
      )
  ),
  0::bigint,
  'PUBLIC has no execute grant on a service-only RPC'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind in ('r', 'p', 'v', 'm')
      and (
        pg_catalog.has_table_privilege('service_role', relation.oid, 'select')
        or pg_catalog.has_table_privilege('service_role', relation.oid, 'insert')
        or pg_catalog.has_table_privilege('service_role', relation.oid, 'update')
        or pg_catalog.has_table_privilege('service_role', relation.oid, 'delete')
        or pg_catalog.has_table_privilege('service_role', relation.oid, 'truncate')
      )
  ),
  0::bigint,
  'service role has no direct public table or view privileges'
);

select * from finish();
rollback;
