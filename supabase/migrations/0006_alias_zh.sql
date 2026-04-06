-- Add alias_zh column: comma-separated Chinese aliases for species search.
-- Example: '乌头,海鲋' for 黑鲷.

alter table public.species_catalog
  add column if not exists alias_zh text;

comment on column public.species_catalog.alias_zh
  is '逗号分隔的中文别名，用于搜索匹配（如 "乌头,海鲋"）';
