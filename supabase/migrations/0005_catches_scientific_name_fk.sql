-- Catches reference species_catalog by scientific_name (stable Latin id), not species_zh.
-- Run after 0004. Requires species_catalog.scientific_name values to be unique.
--
-- Duplicate scientific_name (e.g. legacy 0003 mock + book seed both Lutjanus campechanus):
-- keep the row with the largest id (newer catalog data), re-point catches.species_zh to it,
-- delete older duplicate rows.

-- 1) Reassign catches from duplicate "loser" rows to the canonical Chinese name (keeper).
update public.catches c
set species_zh = k.species_zh
from public.species_catalog loser
join (
  select scientific_name, max(id) as keeper_id
  from public.species_catalog
  group by scientific_name
  having count(*) > 1
) d on loser.scientific_name = d.scientific_name
join public.species_catalog k on k.id = d.keeper_id
where loser.id <> d.keeper_id
  and btrim(c.species_zh) = loser.species_zh;

-- 2) Drop older duplicate catalog rows (same scientific_name, lower id).
delete from public.species_catalog loser
using (
  select scientific_name, max(id) as keeper_id
  from public.species_catalog
  group by scientific_name
  having count(*) > 1
) d
where loser.scientific_name = d.scientific_name
  and loser.id <> d.keeper_id;

-- 3) Self-check: must have no duplicate scientific_name before unique index.
do $$
declare
  dup text;
begin
  select string_agg(scientific_name || ' → ' || zh_list, '; ')
  into dup
  from (
    select
      scientific_name,
      string_agg(species_zh, ', ' order by id) as zh_list,
      count(*) as n
    from public.species_catalog
    group by scientific_name
    having count(*) > 1
  ) t;

  if dup is not null then
    raise exception
      'species_catalog: duplicate scientific_name remains after merge. %',
      dup;
  end if;
end $$;

create unique index if not exists species_catalog_scientific_name_uidx
  on public.species_catalog (scientific_name);

alter table public.catches add column if not exists scientific_name text;

update public.catches c
set scientific_name = sc.scientific_name
from public.species_catalog sc
where btrim(c.species_zh) = sc.species_zh;

update public.catches
set scientific_name = (select scientific_name from public.species_catalog where species_zh = '未确定' limit 1)
where scientific_name is null;

alter table public.catches alter column scientific_name set not null;

alter table public.catches drop constraint if exists catches_species_zh_fkey;

alter table public.catches drop column species_zh;

alter table public.catches
  add constraint catches_scientific_name_fkey
  foreign key (scientific_name) references public.species_catalog (scientific_name)
  on update cascade
  on delete restrict;

drop index if exists catches_review_species_time_idx;

create index catches_review_scientific_time_idx
  on public.catches (review_status, scientific_name, occurred_at_ms desc, id desc);

comment on column public.catches.scientific_name is 'FK to species_catalog.scientific_name; app displays species_zh from catalog join.';
