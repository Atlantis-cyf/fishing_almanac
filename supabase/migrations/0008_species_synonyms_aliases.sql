-- species_synonyms: 学名异名映射（同一物种可能有多个学名）
-- species_aliases: 中文俗名/别名（规范化，替代 alias_zh 逗号拼接）
-- 运行: supabase db push 或在 SQL 编辑器执行

-- 1) 学名异名表
create table if not exists public.species_synonyms (
  id serial primary key,
  synonym text not null,
  canonical_scientific_name text not null
    references public.species_catalog (scientific_name)
    on update cascade on delete cascade,
  source text not null default 'manual'
    check (source in ('manual', 'taxonomic_db', 'ai_detected')),
  created_at timestamptz not null default now()
);

create unique index if not exists species_synonyms_synonym_uidx
  on public.species_synonyms (lower(trim(synonym)));

create index if not exists species_synonyms_canonical_idx
  on public.species_synonyms (canonical_scientific_name);

comment on table public.species_synonyms
  is '学名异名映射：synonym → canonical_scientific_name（species_catalog 中的接受名）';

alter table public.species_synonyms enable row level security;

drop policy if exists "species_synonyms_select_all" on public.species_synonyms;
create policy "species_synonyms_select_all"
  on public.species_synonyms for select
  using (true);

-- 2) 中文俗名/别名表
create table if not exists public.species_aliases (
  id serial primary key,
  alias_zh text not null,
  species_id smallint not null
    references public.species_catalog (id)
    on delete cascade,
  region text,
  created_at timestamptz not null default now()
);

create unique index if not exists species_aliases_alias_species_uidx
  on public.species_aliases (alias_zh, species_id);

create index if not exists species_aliases_alias_idx
  on public.species_aliases (alias_zh);

create index if not exists species_aliases_species_idx
  on public.species_aliases (species_id);

comment on table public.species_aliases
  is '物种中文俗名/别名：多对一映射到 species_catalog.id；同一俗名可用于不同物种（如"石斑"同时指多种石斑鱼）';

alter table public.species_aliases enable row level security;

drop policy if exists "species_aliases_select_all" on public.species_aliases;
create policy "species_aliases_select_all"
  on public.species_aliases for select
  using (true);

-- 3) 将现有 alias_zh 逗号拼接数据迁移到 species_aliases 表
-- 兼容：若当前库还没有 alias_zh 列（例如未执行 0006），则自动跳过本段迁移
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'species_catalog'
      and column_name = 'alias_zh'
  ) then
    insert into public.species_aliases (alias_zh, species_id)
    select trim(a) as alias_zh, sc.id as species_id
    from public.species_catalog sc,
         lateral unnest(string_to_array(sc.alias_zh, ',')) as a
    where sc.alias_zh is not null
      and sc.alias_zh <> ''
      and trim(a) <> ''
    on conflict (alias_zh, species_id) do nothing;
  end if;
end $$;
