begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select no_plan();

select has_table('public', 'families', 'families table exists');
select has_table('public', 'family_memberships', 'family memberships table exists');
select has_table('public', 'child_profiles', 'child profiles table exists');
select has_table('public', 'devices', 'devices table exists');
select has_table('public', 'pairing_codes', 'pairing codes table exists');
select has_table('public', 'learning_events', 'learning events table exists');
select has_table('public', 'progress_snapshots', 'progress snapshots table exists');
select has_table('public', 'reward_inventory', 'reward inventory table exists');
select has_table('public', 'guardian_rewards', 'guardian rewards table exists');
select has_table('public', 'content_drafts', 'content drafts table exists');
select has_table('public', 'content_versions', 'content versions table exists');
select has_table('public', 'content_publications', 'content publications table exists');
select has_table('public', 'audit_log', 'audit log table exists');

select col_type_is('public', 'families', 'id', 'uuid', 'families use UUID IDs');
select col_type_is('public', 'family_memberships', 'id', 'uuid', 'memberships use UUID IDs');
select col_type_is('public', 'child_profiles', 'id', 'uuid', 'profiles use UUID IDs');
select col_type_is('public', 'devices', 'id', 'uuid', 'devices use UUID IDs');
select col_type_is('public', 'pairing_codes', 'id', 'uuid', 'pairing codes use UUID IDs');
select col_type_is('public', 'learning_events', 'id', 'uuid', 'events use UUID row IDs');
select col_type_is('public', 'progress_snapshots', 'id', 'uuid', 'snapshots use UUID IDs');
select col_type_is('public', 'reward_inventory', 'id', 'uuid', 'inventory rows use UUID IDs');
select col_type_is('public', 'guardian_rewards', 'id', 'uuid', 'guardian rewards use UUID IDs');
select col_type_is('public', 'content_drafts', 'id', 'uuid', 'drafts use UUID IDs');
select col_type_is('public', 'content_versions', 'id', 'uuid', 'versions use UUID IDs');
select col_type_is('public', 'content_publications', 'id', 'uuid', 'publications use UUID IDs');
select col_type_is('public', 'audit_log', 'id', 'uuid', 'audit facts use UUID IDs');

select col_is_pk('public', 'families', 'id', 'families UUID is primary key');
select col_is_pk('public', 'family_memberships', 'id', 'memberships UUID is primary key');
select col_is_pk('public', 'child_profiles', 'id', 'profiles UUID is primary key');
select col_is_pk('public', 'devices', 'id', 'devices UUID is primary key');
select col_is_pk('public', 'pairing_codes', 'id', 'pairing UUID is primary key');
select col_is_pk('public', 'learning_events', 'id', 'event row UUID is primary key');
select col_is_pk('public', 'progress_snapshots', 'id', 'snapshot UUID is primary key');
select col_is_pk('public', 'reward_inventory', 'id', 'inventory UUID is primary key');
select col_is_pk('public', 'guardian_rewards', 'id', 'guardian reward UUID is primary key');
select col_is_pk('public', 'content_drafts', 'id', 'draft UUID is primary key');
select col_is_pk('public', 'content_versions', 'id', 'version UUID is primary key');
select col_is_pk('public', 'content_publications', 'id', 'publication UUID is primary key');
select col_is_pk('public', 'audit_log', 'id', 'audit UUID is primary key');

select hasnt_column('public', 'pairing_codes', 'code', 'pairing codes never store plaintext');
select has_column('public', 'pairing_codes', 'code_digest', 'pairing digest exists');
select col_type_is('public', 'pairing_codes', 'code_digest', 'bytea', 'pairing digest is binary');

select has_index('public', 'learning_events', 'learning_events_event_id_key', 'event IDs are globally unique');
select has_index('public', 'learning_events', 'learning_events_device_sequence_key', 'device sequences are unique');
select has_index('public', 'content_versions', 'content_versions_activity_version_key', 'content versions are immutable identities');
select has_index('public', 'content_publications', 'content_publications_one_active_idx', 'one active publication per activity');

select has_function('public', 'is_family_member', array['uuid']);
select has_function('public', 'is_family_guardian', array['uuid']);
select has_function('public', 'has_role', array['text']);

select has_view('public', 'guardian_session_summary', 'guardian session summary exists');
select has_view('public', 'guardian_activity_summary', 'guardian activity summary exists');
select has_view('public', 'guardian_error_patterns', 'guardian error patterns exists');
select has_view('public', 'guardian_reward_summary', 'guardian reward summary exists');

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.learning_events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%response_duration_ms >= 0%'
  ),
  'learning event durations cannot be negative'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.learning_events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%reward_apples >= 0%'
  ),
  'learning event rewards cannot be negative'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.learning_events'::regclass
      and tgname = 'learning_events_append_only'
      and not tgisinternal
  ),
  'learning events are append-only'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.audit_log'::regclass
      and tgname = 'audit_log_append_only'
      and not tgisinternal
  ),
  'audit log is append-only'
);

insert into auth.users (id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000003'),
  ('10000000-0000-4000-8000-000000000004');

insert into public.families (id, name, created_by) values
  (
    '20000000-0000-4000-8000-000000000001',
    'Integrity family A',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'Integrity family B',
    '10000000-0000-4000-8000-000000000002'
  );

insert into public.child_profiles (
  id,
  family_id,
  client_profile_id,
  nickname,
  created_by
) values
  (
    '30000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'profile-a',
    'Child A',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'profile-b',
    'Child B',
    '10000000-0000-4000-8000-000000000002'
  );

select throws_ok(
  $test$
    insert into public.devices (
      id,
      family_id,
      profile_id,
      auth_user_id,
      device_id,
      profile_local_id
    ) values (
      '40000000-0000-4000-8000-000000000002',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000003',
      'cross-family-device',
      'profile-b'
    )
  $test$,
  '23503',
  null,
  'a device cannot bind a profile from another family'
);

insert into public.devices (
  id,
  family_id,
  profile_id,
  auth_user_id,
  device_id,
  profile_local_id,
  paired_at,
  last_sync_at
) values (
  '40000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000004',
  'device-a',
  'profile-a',
  now() - interval '3 hours',
  now() - interval '2 hours'
);

select throws_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      expires_at
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000002',
      decode(repeat('ab', 32), 'hex'),
      '10000000-0000-4000-8000-000000000001',
      now() + interval '10 minutes'
    )
  $test$,
  '23503',
  null,
  'a pairing challenge cannot target another family profile'
);

select throws_ok(
  $test$
    insert into public.progress_snapshots (
      family_id,
      profile_id,
      device_id,
      through_sequence,
      snapshot
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      0,
      '{}'::jsonb
    )
  $test$,
  '23503',
  null,
  'a snapshot family profile and device must be one binding'
);

select throws_ok(
  $test$
    insert into public.reward_inventory (
      family_id,
      profile_id,
      reward_id,
      quantity
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      'apples',
      1
    )
  $test$,
  '23503',
  null,
  'reward inventory cannot cross a family boundary'
);

select throws_ok(
  $test$
    insert into public.guardian_rewards (
      family_id,
      profile_id,
      title,
      required_apples,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      'Cross-family reward',
      1,
      '10000000-0000-4000-8000-000000000002'
    )
  $test$,
  '23503',
  null,
  'guardian rewards cannot cross a family boundary'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      payload
    ) values (
      '50000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000002',
      '40000000-0000-4000-8000-000000000001',
      'profile-a',
      'device-a',
      'session-cross-family',
      1,
      'run_started',
      'addition',
      '2026-07-21T00:00:00Z',
      jsonb_build_object(
        'contract_version', 1,
        'event_id', '50000000-0000-4000-8000-000000000001',
        'profile_id', 'profile-a',
        'device_id', 'device-a',
        'sequence', 1,
        'client_timestamp', '2026-07-21T00:00:00Z',
        'session_id', 'session-cross-family',
        'event_type', 'run_started',
        'activity_id', 'addition',
        'content_version', '1.0.0'
      )
    )
  $test$,
  '23503',
  null,
  'an event family profile and device must be one binding'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      payload
    ) values (
      '50000000-0000-4000-8000-000000000002',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      'profile-a',
      'device-a',
      'session-empty-payload',
      2,
      'answer_submitted',
      'addition',
      '2026-07-21T00:00:01Z',
      '{}'::jsonb
    )
  $test$,
  '23514',
  null,
  'an event rejects a payload missing LearningEventV1 fields'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    ) values (
      '50000000-0000-4000-8000-000000000003',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      'profile-a',
      'device-a',
      'session-mismatched-columns',
      3,
      'answer_submitted',
      'wrong-indexed-activity',
      '2026-07-21T00:01:00Z',
      99999,
      99,
      jsonb_build_object(
        'contract_version', 1,
        'event_id', '50000000-0000-4000-8000-000000000003',
        'profile_id', 'profile-a',
        'device_id', 'device-a',
        'sequence', 3,
        'client_timestamp', '2026-07-21T00:00:02Z',
        'session_id', 'session-mismatched-columns',
        'event_type', 'answer_submitted',
        'activity_id', 'addition',
        'content_version', '1.0.0',
        'question_seed', 42,
        'generator_id', 'addition_pairs',
        'band_id', 'starter',
        'resolved_parameters', jsonb_build_object('sum_max', 10),
        'submitted_answer', 5,
        'correct_answer', 5,
        'correctness', true,
        'response_duration_ms', 123,
        'hints', 0,
        'health_delta', 0,
        'combo', 1,
        'reward_delta', jsonb_build_object('apples', 1)
      )
    )
  $test$,
  '23514',
  null,
  'indexed event columns must equal the canonical payload'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    ) values (
      '50000000-0000-4000-8000-000000000004',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      'profile-a',
      'device-a',
      'session-invalid-type',
      4,
      'answer_submitted',
      'addition',
      '2026-07-21T00:00:03Z',
      123,
      1,
      jsonb_build_object(
        'contract_version', 1,
        'event_id', '50000000-0000-4000-8000-000000000004',
        'profile_id', 'profile-a',
        'device_id', 'device-a',
        'sequence', 4,
        'client_timestamp', '2026-07-21T00:00:03Z',
        'session_id', 'session-invalid-type',
        'event_type', 'answer_submitted',
        'activity_id', 'addition',
        'content_version', '1.0.0',
        'question_seed', 42,
        'generator_id', 'addition_pairs',
        'band_id', 'starter',
        'resolved_parameters', '{}'::jsonb,
        'submitted_answer', 5,
        'correct_answer', 5,
        'correctness', 'true',
        'response_duration_ms', 123,
        'hints', 0,
        'health_delta', 0,
        'combo', 1,
        'reward_delta', jsonb_build_object('apples', 1)
      )
    )
  $test$,
  '23514',
  null,
  'an event rejects LearningEventV1 fields with the wrong JSON type'
);

select lives_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    ) values (
      '50000000-0000-4000-8000-000000000005',
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      '40000000-0000-4000-8000-000000000001',
      'profile-a',
      'device-a',
      'session-valid-answer',
      5,
      'answer_submitted',
      'addition',
      '2026-07-21T00:00:04Z',
      123,
      1,
      jsonb_build_object(
        'contract_version', 1,
        'event_id', '50000000-0000-4000-8000-000000000005',
        'profile_id', 'profile-a',
        'device_id', 'device-a',
        'sequence', 5,
        'client_timestamp', '2026-07-21T00:00:04Z',
        'session_id', 'session-valid-answer',
        'event_type', 'answer_submitted',
        'activity_id', 'addition',
        'content_version', '1.0.0',
        'question_seed', 42,
        'generator_id', 'addition_pairs',
        'band_id', 'starter',
        'resolved_parameters', jsonb_build_object('sum_max', 10),
        'submitted_answer', 5,
        'correct_answer', 5,
        'correctness', true,
        'response_duration_ms', 123,
        'hints', 0,
        'health_delta', 0,
        'combo', 1,
        'reward_delta', jsonb_build_object('apples', 1)
      )
    )
  $test$,
  'a canonical LearningEventV1 answer is accepted'
);

select throws_ok(
  $test$
    update public.learning_events
    set reward_apples = reward_apples + 1
    where event_id = '50000000-0000-4000-8000-000000000005'
  $test$,
  'P0001',
  null,
  'learning events reject direct updates'
);

select throws_ok(
  $test$
    delete from public.learning_events
    where event_id = '50000000-0000-4000-8000-000000000005'
  $test$,
  'P0001',
  null,
  'learning events reject direct deletes'
);

select lives_ok(
  $test$
    select public.delete_learning_events_for_profile_internal(
      '30000000-0000-4000-8000-000000000001'
    )
  $test$,
  'the owner-only privacy primitive can purge one profile event stream'
);

select is(
  (
    select count(*)::integer
    from public.learning_events
    where cloud_profile_id = '30000000-0000-4000-8000-000000000001'
  ),
  0,
  'the privacy primitive removes only the selected profile event stream'
);

select ok(
  coalesce(
    not pg_catalog.has_function_privilege(
      'authenticated',
      pg_catalog.to_regprocedure(
        'public.delete_learning_events_for_profile_internal(uuid)'
      ),
      'EXECUTE'
    ),
    false
  ),
  'authenticated callers cannot execute the internal privacy primitive'
);

select throws_ok(
  $test$
    do $block$
    begin
      truncate table public.learning_events;
      raise exception 'truncate unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'learning events reject truncate'
);

insert into auth.users (id) values
  ('10000000-0000-4000-8000-000000000005');

insert into public.audit_log (
  id,
  actor_id,
  action,
  target_type,
  target_id
) values (
  '70000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000005',
  'integrity_test',
  'fixture',
  'actor-anonymization'
);

select lives_ok(
  $test$
    delete from auth.users
    where id = '10000000-0000-4000-8000-000000000005'
  $test$,
  'auth deletion can anonymize an immutable audit actor through its FK'
);

select is(
  (
    select actor_id
    from public.audit_log
    where id = '70000000-0000-4000-8000-000000000001'
  ),
  null,
  'auth deletion preserves the audit fact with a null actor'
);

select throws_ok(
  $test$
    update public.audit_log
    set action = 'rewritten'
    where id = '70000000-0000-4000-8000-000000000001'
  $test$,
  'P0001',
  null,
  'audit facts still reject direct updates'
);

select throws_ok(
  $test$
    do $block$
    begin
      truncate table public.audit_log;
      raise exception 'truncate unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'audit facts reject truncate'
);

insert into public.pairing_codes (
  id,
  family_id,
  profile_id,
  code_digest,
  created_by,
  expires_at
) values (
  '60000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  decode(repeat('cd', 32), 'hex'),
  '10000000-0000-4000-8000-000000000001',
  now() + interval '10 minutes'
);

select throws_ok(
  $test$
    do $block$
    begin
      insert into public.pairing_codes (
        family_id,
        profile_id,
        code_digest,
        created_by,
        expires_at
      ) values (
        '20000000-0000-4000-8000-000000000002',
        '30000000-0000-4000-8000-000000000002',
        decode(repeat('cd', 32), 'hex'),
        '10000000-0000-4000-8000-000000000002',
        now() + interval '10 minutes'
      );
      raise exception 'duplicate digest unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  '23505',
  null,
  'two active pairing challenges cannot share one digest'
);

select throws_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      expires_at,
      consumed_at
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      decode(repeat('de', 32), 'hex'),
      '10000000-0000-4000-8000-000000000001',
      now() + interval '10 minutes',
      now()
    )
  $test$,
  '23514',
  null,
  'pairing consumption requires both timestamp and actor'
);

select throws_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      expires_at,
      consumed_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      decode(repeat('ef', 32), 'hex'),
      '10000000-0000-4000-8000-000000000001',
      now() + interval '10 minutes',
      '10000000-0000-4000-8000-000000000001'
    )
  $test$,
  '23514',
  null,
  'a pairing consumption actor requires its timestamp'
);

select throws_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      created_at,
      expires_at,
      consumed_at,
      consumed_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      decode(repeat('f0', 32), 'hex'),
      '10000000-0000-4000-8000-000000000001',
      now() - interval '20 minutes',
      now() - interval '10 minutes',
      now(),
      '10000000-0000-4000-8000-000000000001'
    )
  $test$,
  '23514',
  null,
  'an expired pairing challenge cannot be consumed'
);

select lives_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      created_at,
      expires_at,
      invalidated_at
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001',
      decode(repeat('f1', 32), 'hex'),
      '10000000-0000-4000-8000-000000000001',
      now() - interval '20 minutes',
      now() - interval '10 minutes',
      now()
    )
  $test$,
  'an expired pairing challenge can be explicitly invalidated'
);

select lives_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      expires_at
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000002',
      decode(repeat('f1', 32), 'hex'),
      '10000000-0000-4000-8000-000000000002',
      now() + interval '10 minutes'
    )
  $test$,
  'an invalidated digest no longer blocks a new active challenge'
);

update public.pairing_codes
set consumed_at = now(),
    consumed_by = '10000000-0000-4000-8000-000000000001'
where id = '60000000-0000-4000-8000-000000000001';

select lives_ok(
  $test$
    insert into public.pairing_codes (
      family_id,
      profile_id,
      code_digest,
      created_by,
      expires_at
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000002',
      decode(repeat('cd', 32), 'hex'),
      '10000000-0000-4000-8000-000000000002',
      now() + interval '10 minutes'
    )
  $test$,
  'a consumed pairing digest can be safely reused'
);

insert into public.content_versions (
  id,
  activity_id,
  content_version,
  checksum,
  package,
  source_revision,
  created_by
) values
  (
    '80000000-0000-4000-8000-000000000001',
    'activity-a',
    '1.0.0',
    'sha256:' || repeat('a', 64),
    '{}'::jsonb,
    1,
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '80000000-0000-4000-8000-000000000002',
    'activity-a',
    '2.0.0',
    'sha256:' || repeat('b', 64),
    '{}'::jsonb,
    1,
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '80000000-0000-4000-8000-000000000003',
    'activity-b',
    '1.0.0',
    'sha256:' || repeat('c', 64),
    '{}'::jsonb,
    1,
    '10000000-0000-4000-8000-000000000002'
  );

select throws_ok(
  $test$
    insert into public.content_versions (
      activity_id,
      content_version,
      checksum,
      package,
      source_revision,
      created_by
    ) values (
      'activity-a',
      '1.0.0',
      'sha256:' || repeat('d', 64),
      '{}'::jsonb,
      1,
      '10000000-0000-4000-8000-000000000001'
    )
  $test$,
  '23505',
  null,
  'content activity and version identity is unique in behavior'
);

insert into public.content_publications (
  id,
  activity_id,
  content_version,
  version_id,
  published_by
) values
  (
    '90000000-0000-4000-8000-000000000001',
    'activity-a',
    '1.0.0',
    '80000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '90000000-0000-4000-8000-000000000002',
    'activity-b',
    '1.0.0',
    '80000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000002'
  );

select throws_ok(
  $test$
    insert into public.content_publications (
      activity_id,
      content_version,
      version_id,
      published_by
    ) values (
      'activity-a',
      '2.0.0',
      '80000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001'
    )
  $test$,
  '23505',
  null,
  'an activity rejects a second active publication in behavior'
);

select throws_ok(
  $test$
    insert into public.content_publications (
      id,
      activity_id,
      content_version,
      version_id,
      published_by,
      published_at,
      effective_at,
      status,
      retired_at,
      retired_by,
      rollback_of_id
    ) values (
      '90000000-0000-4000-8000-000000000003',
      'activity-b',
      '1.0.0',
      '80000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000002',
      now() - interval '2 days',
      now() - interval '1 day',
      'retired',
      now(),
      '10000000-0000-4000-8000-000000000002',
      '90000000-0000-4000-8000-000000000001'
    )
  $test$,
  '23503',
  null,
  'rollback history cannot reference a different activity'
);

select throws_ok(
  $test$
    insert into public.content_publications (
      id,
      activity_id,
      content_version,
      version_id,
      published_by,
      published_at,
      effective_at,
      status,
      retired_at,
      retired_by,
      rollback_of_id
    ) values (
      '90000000-0000-4000-8000-000000000004',
      'activity-a',
      '2.0.0',
      '80000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      now() - interval '2 days',
      now() - interval '1 day',
      'retired',
      now(),
      '10000000-0000-4000-8000-000000000001',
      '90000000-0000-4000-8000-000000000004'
    )
  $test$,
  '23514',
  null,
  'a publication cannot be its own rollback source'
);

select lives_ok(
  $test$
    insert into public.content_publications (
      id,
      activity_id,
      content_version,
      version_id,
      published_by,
      published_at,
      effective_at,
      status
    ) values (
      '90000000-0000-4000-8000-000000000005',
      'activity-a',
      '2.0.0',
      '80000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      now(),
      now() + interval '1 day',
      'pending'
    )
  $test$,
  'one pending publication can coexist with the active pointer'
);

select throws_ok(
  $test$
    insert into public.content_publications (
      activity_id,
      content_version,
      version_id,
      published_by,
      published_at,
      effective_at,
      status
    ) values (
      'activity-a',
      '2.0.0',
      '80000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      now(),
      now() + interval '2 days',
      'pending'
    )
  $test$,
  '23505',
  null,
  'an activity has at most one pending publication'
);

select throws_ok(
  $test$
    do $block$
    begin
      insert into public.content_publications (
        activity_id,
        content_version,
        version_id,
        published_by,
        published_at,
        effective_at,
        status
      ) values (
        'activity-b',
        '1.0.0',
        '80000000-0000-4000-8000-000000000003',
        '10000000-0000-4000-8000-000000000002',
        now() - interval '2 days',
        now() - interval '1 day',
        'pending'
      );
      raise exception 'already-due pending publication unexpectedly succeeded'
        using errcode = 'P0002';
    end
    $block$
  $test$,
  '23514',
  null,
  'a newly scheduled publication must still be in the future'
);

select throws_ok(
  $test$
    do $block$
    begin
      update public.content_publications
      set published_by = '10000000-0000-4000-8000-000000000002'
      where id = '90000000-0000-4000-8000-000000000001';
      raise exception 'publication identity update unexpectedly succeeded'
        using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'publication actor and identity are immutable'
);

select lives_ok(
  $test$
    update public.content_publications
    set status = 'retired',
        retired_at = now(),
        retired_by = '10000000-0000-4000-8000-000000000002'
    where id = '90000000-0000-4000-8000-000000000002'
  $test$,
  'an active publication permits its one-way retirement transition'
);

select throws_ok(
  $test$
    do $block$
    begin
      delete from public.content_publications
      where id = '90000000-0000-4000-8000-000000000001';
      raise exception 'publication delete unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'publication history rejects delete'
);

select throws_ok(
  $test$
    do $block$
    begin
      truncate table public.content_publications;
      raise exception 'publication truncate unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'publication history rejects truncate'
);

select throws_ok(
  $test$
    do $block$
    begin
      truncate table public.content_versions cascade;
      raise exception 'version truncate unexpectedly succeeded' using errcode = 'P0002';
    end
    $block$
  $test$,
  'P0001',
  null,
  'immutable content versions reject truncate'
);

insert into public.devices (
  id,
  family_id,
  profile_id,
  auth_user_id,
  device_id,
  profile_local_id,
  paired_at,
  last_sync_at
) values (
  '40000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003',
  'device-a-older',
  'profile-a',
  now() - interval '30 hours',
  now() - interval '26 hours'
);

insert into public.learning_events (
  event_id,
  family_id,
  cloud_profile_id,
  internal_device_id,
  profile_id,
  device_id,
  session_id,
  local_sequence,
  event_type,
  activity_id,
  client_timestamp,
  response_duration_ms,
  reward_apples,
  payload
) values
  (
    '51000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-complete',
    10,
    'collection_unlocked',
    null,
    '2026-07-21T00:00:00Z',
    0,
    0,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000001","profile_id":"profile-a","device_id":"device-a","sequence":10,"client_timestamp":"2026-07-21T00:00:00Z","session_id":"session-complete","event_type":"collection_unlocked","collection_id":"first-map"}'::jsonb
  ),
  (
    '51000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-complete',
    11,
    'run_started',
    'addition',
    '2026-07-21T00:01:00Z',
    0,
    0,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000002","profile_id":"profile-a","device_id":"device-a","sequence":11,"client_timestamp":"2026-07-21T00:01:00Z","session_id":"session-complete","event_type":"run_started","activity_id":"addition","content_version":"1.0.0"}'::jsonb
  ),
  (
    '51000000-0000-4000-8000-000000000003',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-complete',
    12,
    'answer_submitted',
    'addition',
    '2026-07-21T00:02:00Z',
    100,
    1,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000003","profile_id":"profile-a","device_id":"device-a","sequence":12,"client_timestamp":"2026-07-21T00:02:00Z","session_id":"session-complete","event_type":"answer_submitted","activity_id":"addition","content_version":"1.0.0","question_seed":5,"generator_id":"addition_pairs","band_id":"starter","resolved_parameters":{"sum_max":10},"submitted_answer":5,"correct_answer":5,"correctness":true,"response_duration_ms":100,"hints":0,"health_delta":0,"combo":1,"reward_delta":{"apples":1}}'::jsonb
  ),
  (
    '51000000-0000-4000-8000-000000000004',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-complete',
    13,
    'run_completed',
    null,
    '2026-07-21T00:03:00Z',
    0,
    2,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000004","profile_id":"profile-a","device_id":"device-a","sequence":13,"client_timestamp":"2026-07-21T00:03:00Z","session_id":"session-complete","event_type":"run_completed","completion_reason":"cleared","final_score":1,"final_health":3,"earned_rewards":{"apples":2}}'::jsonb
  ),
  (
    '51000000-0000-4000-8000-000000000005',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-complete',
    14,
    'coupon_earned',
    null,
    '2026-07-21T00:04:00Z',
    0,
    0,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000005","profile_id":"profile-a","device_id":"device-a","sequence":14,"client_timestamp":"2026-07-21T00:04:00Z","session_id":"session-complete","event_type":"coupon_earned","coupon_id":"brave-run"}'::jsonb
  ),
  (
    '51000000-0000-4000-8000-000000000006',
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001',
    'profile-a',
    'device-a',
    'session-incomplete',
    15,
    'run_started',
    'addition',
    '2026-07-21T01:00:00Z',
    0,
    0,
    '{"contract_version":1,"event_id":"51000000-0000-4000-8000-000000000006","profile_id":"profile-a","device_id":"device-a","sequence":15,"client_timestamp":"2026-07-21T01:00:00Z","session_id":"session-incomplete","event_type":"run_started","activity_id":"addition","content_version":"1.0.0"}'::jsonb
  );

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    )
    select
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      16,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload || jsonb_build_object('sequence', 16)
    from public.learning_events
    where event_id = '51000000-0000-4000-8000-000000000002'
  $test$,
  '23505',
  null,
  'event IDs are globally unique in behavior'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    )
    select
      '51000000-0000-4000-8000-000000000007',
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload || jsonb_build_object(
        'event_id', '51000000-0000-4000-8000-000000000007'
      )
    from public.learning_events
    where event_id = '51000000-0000-4000-8000-000000000002'
  $test$,
  '23505',
  null,
  'device sequence pairs are unique in behavior'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    )
    select
      '51000000-0000-4000-8000-000000000008',
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      17,
      event_type,
      activity_id,
      client_timestamp,
      -1,
      reward_apples,
      payload || jsonb_build_object(
        'event_id', '51000000-0000-4000-8000-000000000008',
        'sequence', 17,
        'response_duration_ms', -1
      )
    from public.learning_events
    where event_id = '51000000-0000-4000-8000-000000000003'
  $test$,
  '23514',
  null,
  'negative event durations are rejected in behavior'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    )
    select
      '51000000-0000-4000-8000-000000000009',
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      18,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload || jsonb_build_object(
        'event_id', '51000000-0000-4000-8000-000000000009',
        'sequence', 18,
        'unexpected', true
      )
    from public.learning_events
    where event_id = '51000000-0000-4000-8000-000000000003'
  $test$,
  '23514',
  null,
  'LearningEventV1 rejects unknown payload fields'
);

select throws_ok(
  $test$
    insert into public.learning_events (
      event_id,
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      local_sequence,
      event_type,
      activity_id,
      client_timestamp,
      response_duration_ms,
      reward_apples,
      payload
    )
    select
      '51000000-0000-4000-8000-00000000000a',
      family_id,
      cloud_profile_id,
      internal_device_id,
      profile_id,
      device_id,
      session_id,
      19,
      event_type,
      activity_id,
      '2026-07-21T00:01:00Z',
      response_duration_ms,
      reward_apples,
      payload || jsonb_build_object(
        'event_id', '51000000-0000-4000-8000-00000000000a',
        'sequence', 19,
        'client_timestamp', '2026-07-21T00:01:00.000Z'
      )
    from public.learning_events
    where event_id = '51000000-0000-4000-8000-000000000002'
  $test$,
  '23514',
  null,
  'LearningEventV1 timestamps remain canonical UTC seconds'
);

select lives_ok(
  $test$
    do $block$
    declare
      completed_rows integer;
      incomplete_rows integer;
      actual_started_at timestamptz;
      actual_completed_at timestamptz;
    begin
      select count(*)::integer
      into completed_rows
      from public.guardian_session_summary
      where session_id = 'session-complete';

      select count(*)::integer
      into incomplete_rows
      from public.guardian_session_summary
      where session_id = 'session-incomplete';

      select started_at, completed_at
      into actual_started_at, actual_completed_at
      from public.guardian_session_summary
      where session_id = 'session-complete';

      if completed_rows <> 1
        or incomplete_rows <> 0
        or actual_started_at <> '2026-07-21T00:01:00Z'::timestamptz
        or actual_completed_at <> '2026-07-21T00:03:00Z'::timestamptz then
        raise exception 'session aggregate lifecycle is incorrect'
          using errcode = 'P0002';
      end if;
    end
    $block$
  $test$,
  'session aggregates use run boundaries and omit incomplete runs'
);

select has_view(
  'public',
  'guardian_profile_sync_summary',
  'guardian profile sync summary exists'
);

select lives_ok(
  $test$
    do $block$
    declare
      profile_a_latest timestamptz;
      profile_a_stale boolean;
      profile_b_latest timestamptz;
      profile_b_stale boolean;
      expected_latest timestamptz;
    begin
      select max(last_sync_at)
      into expected_latest
      from public.devices
      where profile_id = '30000000-0000-4000-8000-000000000001'
        and disconnected_at is null;

      select latest_sync_at, is_stale
      into profile_a_latest, profile_a_stale
      from public.guardian_profile_sync_summary
      where profile_id = '30000000-0000-4000-8000-000000000001';

      select latest_sync_at, is_stale
      into profile_b_latest, profile_b_stale
      from public.guardian_profile_sync_summary
      where profile_id = '30000000-0000-4000-8000-000000000002';

      if profile_a_latest is distinct from expected_latest
        or profile_a_stale
        or profile_b_latest is not null
        or not profile_b_stale then
        raise exception 'profile sync staleness is incorrect' using errcode = 'P0002';
      end if;
    end
    $block$
  $test$,
  'sync staleness uses the latest connected device timestamp'
);

insert into public.family_memberships (
  family_id,
  user_id,
  role
) values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'owner'
);

update public.families
set deleted_at = now()
where id = '20000000-0000-4000-8000-000000000001';

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);

select is(
  public.is_family_member('20000000-0000-4000-8000-000000000001'),
  false,
  'soft-deleted families do not authorize membership'
);

select is(
  public.is_family_guardian('20000000-0000-4000-8000-000000000001'),
  false,
  'soft-deleted families do not authorize guardian access'
);

select is(
  public.has_role('owner'),
  false,
  'a role from only a soft-deleted family is inactive'
);

select ok(
  (
    select function.prosecdef
      and function.proconfig @> array['search_path=""']::text[]
    from pg_catalog.pg_proc function
    join pg_catalog.pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'is_family_member'
  ),
  'family helpers remain security definer with an empty search path'
);

select * from finish();
rollback;
