-- species_catalog: 支持用户贡献鱼种 + AI 识别日志。
-- 运行: supabase db push 或在 SQL 编辑器执行。

-- 1) species_catalog 新增字段

alter table public.species_catalog
  add column if not exists source text not null default 'official'
    check (source in ('official', 'user_contributed'));

alter table public.species_catalog
  add column if not exists status text not null default 'approved'
    check (status in ('approved', 'pending', 'rejected'));

alter table public.species_catalog
  add column if not exists contributed_by uuid references auth.users(id) on delete set null;

alter table public.species_catalog
  add column if not exists contributed_image_url text;

comment on column public.species_catalog.source
  is '数据来源: official=官方维护, user_contributed=用户上传AI识别后自动创建';

comment on column public.species_catalog.status
  is '审核状态: approved=已审核可公开, pending=待审核, rejected=已拒绝';

comment on column public.species_catalog.contributed_by
  is '贡献该鱼种的首位用户 id（仅 user_contributed）';

comment on column public.species_catalog.contributed_image_url
  is '用户授权的鱼种图片 URL（存于 species-images bucket）';

create index if not exists species_catalog_status_idx
  on public.species_catalog (status);

create index if not exists species_catalog_source_idx
  on public.species_catalog (source);

-- 2) AI 识别日志表

create table if not exists public.species_identify_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  is_fish boolean,
  species_zh text,
  scientific_name text,
  confidence numeric,
  raw_label text,
  model_engine text,
  model_id text,
  image_url text,
  error_message text,
  created_at timestamptz not null default now()
);

comment on table public.species_identify_logs
  is 'AI 鱼种识别日志，包含非鱼种上传记录（is_fish=false）用于数据分析';

create index if not exists identify_logs_user_time_idx
  on public.species_identify_logs (user_id, created_at desc);

create index if not exists identify_logs_is_fish_idx
  on public.species_identify_logs (is_fish);

alter table public.species_identify_logs enable row level security;
