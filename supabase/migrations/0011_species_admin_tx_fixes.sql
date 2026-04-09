-- Admin workflow transactional fixes:
-- 1) replace aliases in one transaction
-- 2) snapshot restore via DB transaction
-- 3) strengthen merge B->A guard (target A must not be merged)

create or replace function public.admin_replace_species_aliases(
  p_species_id smallint,
  p_aliases text[]
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted integer := 0;
begin
  if p_species_id is null then
    raise exception 'species id cannot be null';
  end if;

  if not exists (select 1 from public.species_catalog where id = p_species_id) then
    raise exception 'species not found: %', p_species_id;
  end if;

  delete from public.species_aliases where species_id = p_species_id;

  if p_aliases is not null and array_length(p_aliases, 1) > 0 then
    insert into public.species_aliases (alias_zh, species_id, region)
    select distinct trim(a), p_species_id, null
    from unnest(p_aliases) a
    where trim(coalesce(a, '')) <> ''
    on conflict do nothing;
    get diagnostics v_inserted = row_count;
  end if;

  return jsonb_build_object(
    'species_id', p_species_id,
    'aliases_inserted', v_inserted
  );
end;
$$;

create or replace function public.admin_restore_species_snapshot(
  p_snapshot_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  if p_snapshot_id is null then
    raise exception 'snapshot id cannot be null';
  end if;

  if not exists (
    select 1
    from public.species_catalog_snapshot_rows
    where snapshot_id = p_snapshot_id
  ) then
    raise exception 'snapshot not found or empty: %', p_snapshot_id;
  end if;

  insert into public.species_catalog (
    species_zh,
    scientific_name,
    taxonomy_zh,
    is_rare,
    image_url,
    max_length_m,
    max_weight_kg,
    description_zh,
    name_en,
    encyclopedia_category,
    rarity_display,
    alias_zh,
    source,
    status,
    contributed_by,
    contributed_image_url
  )
  select
    (r.row_data->>'species_zh')::text as species_zh,
    coalesce((r.row_data->>'scientific_name')::text, r.scientific_name) as scientific_name,
    coalesce((r.row_data->>'taxonomy_zh')::text, '') as taxonomy_zh,
    coalesce((r.row_data->>'is_rare')::boolean, false) as is_rare,
    coalesce((r.row_data->>'image_url')::text, 'https://via.placeholder.com/1200x800?text=species') as image_url,
    coalesce((r.row_data->>'max_length_m')::double precision, 0) as max_length_m,
    coalesce((r.row_data->>'max_weight_kg')::double precision, 0) as max_weight_kg,
    coalesce((r.row_data->>'description_zh')::text, '') as description_zh,
    nullif((r.row_data->>'name_en')::text, '') as name_en,
    nullif((r.row_data->>'encyclopedia_category')::text, '') as encyclopedia_category,
    nullif((r.row_data->>'rarity_display')::text, '') as rarity_display,
    nullif((r.row_data->>'alias_zh')::text, '') as alias_zh,
    coalesce(nullif((r.row_data->>'source')::text, ''), 'official') as source,
    coalesce(nullif((r.row_data->>'status')::text, ''), 'approved') as status,
    nullif((r.row_data->>'contributed_by')::uuid::text, '')::uuid as contributed_by,
    nullif((r.row_data->>'contributed_image_url')::text, '') as contributed_image_url
  from public.species_catalog_snapshot_rows r
  where r.snapshot_id = p_snapshot_id
  on conflict (scientific_name) do update set
    species_zh = excluded.species_zh,
    taxonomy_zh = excluded.taxonomy_zh,
    is_rare = excluded.is_rare,
    image_url = excluded.image_url,
    max_length_m = excluded.max_length_m,
    max_weight_kg = excluded.max_weight_kg,
    description_zh = excluded.description_zh,
    name_en = excluded.name_en,
    encyclopedia_category = excluded.encyclopedia_category,
    rarity_display = excluded.rarity_display,
    alias_zh = excluded.alias_zh,
    source = excluded.source,
    status = excluded.status,
    contributed_by = excluded.contributed_by,
    contributed_image_url = excluded.contributed_image_url;

  get diagnostics v_rows = row_count;

  delete from public.species_aliases where id <> 0;
  delete from public.species_synonyms where id <> 0;

  insert into public.species_aliases (alias_zh, species_id, region)
  select
    (a.alias_data->>'alias_zh')::text as alias_zh,
    (a.alias_data->>'species_id')::smallint as species_id,
    nullif((a.alias_data->>'region')::text, '') as region
  from public.species_aliases_snapshot_rows a
  where a.snapshot_id = p_snapshot_id
    and coalesce((a.alias_data->>'alias_zh')::text, '') <> '';

  insert into public.species_synonyms (synonym, canonical_scientific_name, source)
  select
    (s.synonym_data->>'synonym')::text as synonym,
    (s.synonym_data->>'canonical_scientific_name')::text as canonical_scientific_name,
    coalesce(nullif((s.synonym_data->>'source')::text, ''), 'manual') as source
  from public.species_synonyms_snapshot_rows s
  where s.snapshot_id = p_snapshot_id
    and coalesce((s.synonym_data->>'synonym')::text, '') <> ''
    and coalesce((s.synonym_data->>'canonical_scientific_name')::text, '') <> '';

  return jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'restored_rows', v_rows
  );
end;
$$;

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

  if v_target.merged_into_species_id is not null then
    raise exception 'target species already merged into %', v_target.merged_into_species_id;
  end if;

  if v_source.merged_into_species_id is not null then
    raise exception 'source species already merged into %', v_source.merged_into_species_id;
  end if;

  if lower(trim(v_target.scientific_name)) = lower(trim('Other'))
     or lower(trim(v_source.scientific_name)) = lower(trim('Other')) then
    raise exception 'system species Other cannot be merged';
  end if;

  update public.catches
  set scientific_name = v_target.scientific_name
  where scientific_name = v_source.scientific_name;
  get diagnostics v_catches_relinked = row_count;

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

  insert into public.species_synonyms (synonym, canonical_scientific_name, source)
  select s.synonym, v_target.scientific_name, coalesce(s.source, 'manual')
  from public.species_synonyms s
  where s.canonical_scientific_name = v_source.scientific_name
    and lower(trim(s.synonym)) <> lower(trim(v_target.scientific_name))
  on conflict do nothing;
  get diagnostics v_synonyms_inserted = row_count;

  delete from public.species_synonyms
  where canonical_scientific_name = v_source.scientific_name;

  if p_add_source_scientific_as_synonym
     and lower(trim(v_source.scientific_name)) <> lower(trim(v_target.scientific_name)) then
    insert into public.species_synonyms (synonym, canonical_scientific_name, source)
    values (v_source.scientific_name, v_target.scientific_name, 'manual')
    on conflict do nothing;
    v_source_scientific_synonym_added := true;
  end if;

  update public.species_catalog
  set status = 'rejected',
      merged_into_species_id = p_target_species_id,
      merged_at = now(),
      merge_note = coalesce(merge_note, '') ||
        case when coalesce(merge_note, '') = '' then '' else E'\n' end ||
        format('merged into %s by %s at %s', v_target.scientific_name, coalesce(p_actor_user_id::text, 'unknown'), now()::text)
  where id = p_source_species_id;

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
