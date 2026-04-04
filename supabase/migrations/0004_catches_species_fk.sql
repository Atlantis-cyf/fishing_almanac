-- Strong bind catches.species_zh -> species_catalog.species_zh (FK).
-- Run after 0003_species_catalog.sql.

insert into public.species_catalog (
  species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display
)
select
  v.species_zh,
  v.scientific_name,
  '',
  false,
  coalesce((select sc.image_url from public.species_catalog sc where sc.id = 1 limit 1), ''),
  0,
  0,
  v.description_zh,
  null,
  null,
  null
from (
  values
    ('未确定', 'Indeterminata', '用户未指定或与图鉴未匹配的占位物种'),
    ('未命名鱼种', 'Unnamed', '历史或占位用中文名')
) as v(species_zh, scientific_name, description_zh)
where not exists (select 1 from public.species_catalog s where s.species_zh = v.species_zh);

insert into public.species_catalog (
  species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display
)
select distinct
  trim(c.species_zh),
  trim(c.species_zh),
  '',
  false,
  coalesce((select sc.image_url from public.species_catalog sc where sc.id = 1 limit 1), ''),
  0,
  0,
  '由 catches 表迁移自动补齐，请在 species_catalog 中完善学名与配图',
  null,
  null,
  null
from public.catches c
where trim(c.species_zh) <> ''
  and not exists (select 1 from public.species_catalog s where s.species_zh = trim(c.species_zh));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'catches_species_zh_fkey'
  ) then
    alter table public.catches
      add constraint catches_species_zh_fkey
      foreign key (species_zh) references public.species_catalog (species_zh)
      on update cascade
      on delete restrict;
  end if;
end $$;

comment on constraint catches_species_zh_fkey on public.catches is
  '鱼获鱼种中文名必须存在于 species_catalog；更新中文名时级联 catches。';
