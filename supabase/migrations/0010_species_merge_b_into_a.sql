-- Species merge operation (B -> A):
-- keep A as canonical species, archive B, and migrate references.

alter table public.species_catalog
  add column if not exists merged_into_species_id smallint
    references public.species_catalog (id) on delete set null;

alter table public.species_catalog
  add column if not exists merged_at timestamptz;

alter table public.species_catalog
  add column if not exists merge_note text;

create index if not exists species_catalog_merged_into_idx
  on public.species_catalog (merged_into_species_id);

create or replace function public.admin_merge_species_b_into_a(
  p_target_species_id smallint,
  p_source_species_id smallint,
  p_actor_user_id uuid default null,
  p_add_source_scientific_as_synonym boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.species_catalog%rowtype;
  v_source public.species_catalog%rowtype;
  v_catches_relinked integer := 0;
  v_aliases_inserted integer := 0;
  v_synonyms_inserted integer := 0;
  v_source_scientific_synonym_added boolean := false;
begin
  if p_target_species_id is null or p_source_species_id is null then
    raise exception 'target/source species id cannot be null';
  end if;
  if p_target_species_id = p_source_species_id then
    raise exception 'target/source species id cannot be equal';
  end if;

  select * into v_target
  from public.species_catalog
  where id = p_target_species_id
  for update;

  if not found then
    raise exception 'target species not found: %', p_target_species_id;
  end if;

  select * into v_source
  from public.species_catalog
  where id = p_source_species_id
  for update;

  if not found then
    raise exception 'source species not found: %', p_source_species_id;
  end if;

  if v_source.merged_into_species_id is not null then
    raise exception 'source species already merged into %', v_source.merged_into_species_id;
  end if;

  if lower(trim(v_target.scientific_name)) = lower(trim('Other'))
     or lower(trim(v_source.scientific_name)) = lower(trim('Other')) then
    raise exception 'system species Other cannot be merged';
  end if;

  -- 1) Move catches FK scientific_name from B to A
  update public.catches
  set scientific_name = v_target.scientific_name
  where scientific_name = v_source.scientific_name;
  get diagnostics v_catches_relinked = row_count;

  -- 2) Move aliases (insert only missing aliases, then delete old links from B)
  insert into public.species_aliases (alias_zh, species_id, region)
  select a.alias_zh, p_target_species_id, a.region
  from public.species_aliases a
  where a.species_id = p_source_species_id
    and not exists (
      select 1
      from public.species_aliases t
      where t.species_id = p_target_species_id
        and lower(trim(t.alias_zh)) = lower(trim(a.alias_zh))
    );
  get diagnostics v_aliases_inserted = row_count;

  delete from public.species_aliases
  where species_id = p_source_species_id;

  -- 3) Move synonyms canonical name from B to A (dedupe by unique synonym index)
  insert into public.species_synonyms (synonym, canonical_scientific_name, source)
  select s.synonym, v_target.scientific_name, coalesce(s.source, 'manual')
  from public.species_synonyms s
  where s.canonical_scientific_name = v_source.scientific_name
    and lower(trim(s.synonym)) <> lower(trim(v_target.scientific_name))
  on conflict do nothing;
  get diagnostics v_synonyms_inserted = row_count;

  delete from public.species_synonyms
  where canonical_scientific_name = v_source.scientific_name;

  -- 4) Optional: add B scientific_name as synonym of A
  if p_add_source_scientific_as_synonym
     and lower(trim(v_source.scientific_name)) <> lower(trim(v_target.scientific_name)) then
    insert into public.species_synonyms (synonym, canonical_scientific_name, source)
    values (v_source.scientific_name, v_target.scientific_name, 'manual')
    on conflict do nothing;
    v_source_scientific_synonym_added := true;
  end if;

  -- 5) Archive B and mark merge direction B -> A
  update public.species_catalog
  set status = 'rejected',
      merged_into_species_id = p_target_species_id,
      merged_at = now(),
      merge_note = coalesce(merge_note, '') ||
        case when coalesce(merge_note, '') = '' then '' else E'\n' end ||
        format('merged into %s by %s at %s', v_target.scientific_name, coalesce(p_actor_user_id::text, 'unknown'), now()::text)
  where id = p_source_species_id;

  -- Ensure A remains canonical
  update public.species_catalog
  set merged_into_species_id = null,
      merged_at = null
  where id = p_target_species_id;

  return jsonb_build_object(
    'merge_direction', 'B_into_A',
    'target_species_id', p_target_species_id,
    'source_species_id', p_source_species_id,
    'target_scientific_name', v_target.scientific_name,
    'source_scientific_name', v_source.scientific_name,
    'catches_relinked', v_catches_relinked,
    'aliases_inserted_into_target', v_aliases_inserted,
    'synonyms_inserted_into_target', v_synonyms_inserted,
    'source_scientific_synonym_added', v_source_scientific_synonym_added
  );
end;
$$;
