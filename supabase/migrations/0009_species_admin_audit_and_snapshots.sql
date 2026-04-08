-- Species admin operations: audit logs + rollback snapshots
-- Run: supabase db push (or execute in SQL editor)

create table if not exists public.species_admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  species_id smallint,
  species_scientific_name text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb,
  created_at timestamptz not null default now()
);

comment on table public.species_admin_audit_logs
  is '物种后台管理操作日志（可审计，可用于问题追踪）';

create index if not exists species_admin_audit_logs_time_idx
  on public.species_admin_audit_logs (created_at desc);

create index if not exists species_admin_audit_logs_actor_idx
  on public.species_admin_audit_logs (actor_user_id, created_at desc);

create index if not exists species_admin_audit_logs_species_idx
  on public.species_admin_audit_logs (species_id, created_at desc);

alter table public.species_admin_audit_logs enable row level security;

drop policy if exists "species_admin_audit_logs_select_all" on public.species_admin_audit_logs;
create policy "species_admin_audit_logs_select_all"
  on public.species_admin_audit_logs for select
  using (true);

-- Snapshot head
create table if not exists public.species_catalog_snapshots (
  id uuid primary key default gen_random_uuid(),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

comment on table public.species_catalog_snapshots
  is '物种库快照头表；用于回滚图鉴';

create index if not exists species_catalog_snapshots_time_idx
  on public.species_catalog_snapshots (created_at desc);

alter table public.species_catalog_snapshots enable row level security;

drop policy if exists "species_catalog_snapshots_select_all" on public.species_catalog_snapshots;
create policy "species_catalog_snapshots_select_all"
  on public.species_catalog_snapshots for select
  using (true);

-- Snapshot of species_catalog rows
create table if not exists public.species_catalog_snapshot_rows (
  id bigserial primary key,
  snapshot_id uuid not null references public.species_catalog_snapshots(id) on delete cascade,
  scientific_name text not null,
  row_data jsonb not null
);

create index if not exists species_catalog_snapshot_rows_snapshot_idx
  on public.species_catalog_snapshot_rows (snapshot_id);

create index if not exists species_catalog_snapshot_rows_scientific_idx
  on public.species_catalog_snapshot_rows (snapshot_id, scientific_name);

alter table public.species_catalog_snapshot_rows enable row level security;

drop policy if exists "species_catalog_snapshot_rows_select_all" on public.species_catalog_snapshot_rows;
create policy "species_catalog_snapshot_rows_select_all"
  on public.species_catalog_snapshot_rows for select
  using (true);

-- Snapshot of normalized aliases
create table if not exists public.species_aliases_snapshot_rows (
  id bigserial primary key,
  snapshot_id uuid not null references public.species_catalog_snapshots(id) on delete cascade,
  alias_data jsonb not null
);

create index if not exists species_aliases_snapshot_rows_snapshot_idx
  on public.species_aliases_snapshot_rows (snapshot_id);

alter table public.species_aliases_snapshot_rows enable row level security;

drop policy if exists "species_aliases_snapshot_rows_select_all" on public.species_aliases_snapshot_rows;
create policy "species_aliases_snapshot_rows_select_all"
  on public.species_aliases_snapshot_rows for select
  using (true);

-- Snapshot of scientific synonyms
create table if not exists public.species_synonyms_snapshot_rows (
  id bigserial primary key,
  snapshot_id uuid not null references public.species_catalog_snapshots(id) on delete cascade,
  synonym_data jsonb not null
);

create index if not exists species_synonyms_snapshot_rows_snapshot_idx
  on public.species_synonyms_snapshot_rows (snapshot_id);

alter table public.species_synonyms_snapshot_rows enable row level security;

drop policy if exists "species_synonyms_snapshot_rows_select_all" on public.species_synonyms_snapshot_rows;
create policy "species_synonyms_snapshot_rows_select_all"
  on public.species_synonyms_snapshot_rows for select
  using (true);
