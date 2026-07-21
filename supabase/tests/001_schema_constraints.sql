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

select * from finish();
rollback;
