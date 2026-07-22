create table public.content_drafts (
  id uuid primary key default extensions.gen_random_uuid(),
  activity_id text not null check (char_length(activity_id) between 1 and 128),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  revision integer not null default 1 check (revision >= 1),
  package jsonb not null check (jsonb_typeof(package) = 'object'),
  validation_report jsonb check (validation_report is null or jsonb_typeof(validation_report) = 'object'),
  validation_checksum text check (
    validation_checksum is null or validation_checksum ~ '^sha256:[0-9a-f]{64}$'
  ),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint content_drafts_activity_id_key unique (activity_id)
);

create table public.content_versions (
  id uuid primary key default extensions.gen_random_uuid(),
  activity_id text not null check (char_length(activity_id) between 1 and 128),
  content_version text not null check (
    content_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
  ),
  checksum text not null check (checksum ~ '^sha256:[0-9a-f]{64}$'),
  package jsonb not null check (jsonb_typeof(package) = 'object'),
  source_draft_id uuid references public.content_drafts(id) on delete set null,
  source_revision integer not null check (source_revision >= 1),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint content_versions_activity_version_key unique (activity_id, content_version),
  constraint content_versions_identity_key unique (id, activity_id, content_version),
  constraint content_versions_checksum_key unique (checksum)
);

create trigger content_versions_append_only
before update or delete on public.content_versions
for each row execute function public.reject_append_only_mutation();

create table public.content_publications (
  id uuid primary key default extensions.gen_random_uuid(),
  activity_id text not null,
  content_version text not null,
  version_id uuid not null,
  published_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz not null default now(),
  retired_at timestamptz,
  retired_by uuid references auth.users(id) on delete restrict,
  rollback_of_id uuid references public.content_publications(id) on delete restrict,
  constraint content_publications_version_identity_fkey
    foreign key (version_id, activity_id, content_version)
    references public.content_versions(id, activity_id, content_version)
    on delete restrict,
  check ((retired_at is null and retired_by is null) or (retired_at is not null and retired_by is not null)),
  check (retired_at is null or retired_at >= published_at)
);

create unique index content_publications_one_active_idx
  on public.content_publications (activity_id)
  where retired_at is null;
create index content_publications_history_idx
  on public.content_publications (activity_id, published_at desc);

create table public.audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  family_id uuid references public.families(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check (char_length(action) between 1 and 96),
  target_type text not null check (char_length(target_type) between 1 and 64),
  target_id text not null check (char_length(target_id) between 1 and 160),
  request_id uuid,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  check (
    action not like 'ai_patch_%'
    or metadata - array['instruction', 'draft_revision', 'patch', 'provider', 'status'] = '{}'::jsonb
  )
);

create index audit_log_family_created_idx
  on public.audit_log (family_id, created_at desc)
  where family_id is not null;
create index audit_log_target_idx on public.audit_log (target_type, target_id, created_at desc);

create trigger audit_log_append_only
before update or delete on public.audit_log
for each row execute function public.reject_append_only_mutation();
