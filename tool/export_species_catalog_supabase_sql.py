#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate full-replace SQL for species catalog from the new CSV.

Goals:
- Replace official catalog fields from CSV (aligned with existing DB unique keys)
- Keep runtime fields intact: source/status/contributed_*
- Refresh species_aliases from CSV alias_zh values
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

DEFAULT_BOOK = Path(r"D:\fishingapp-cursor\book\2.0豆包\抓取图片")
DEFAULT_TAXONOMY_CSV = DEFAULT_BOOK / "species_catalog_wikipedia_images_filled.csv"
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_SQL = ROOT / "supabase" / "seed" / "species_catalog_from_book_upsert.sql"
PLACEHOLDER_IMAGE_URL = "https://via.placeholder.com/1200x800?text=species"


def sql_str(s: str) -> str:
    return "'" + (s or "").replace("\\", "\\\\").replace("'", "''") + "'"


def parse_bool(raw: str) -> bool:
    t = (raw or "").strip().upper()
    return t in ("TRUE", "1", "YES", "Y", "T")


def norm_rarity_display(raw: str) -> str | None:
    t = (raw or "").strip()
    if not t:
        return None
    if t.upper() in ("FALSE", "TRUE", "NONE", ""):
        return None
    return t


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row:
                continue
            rows.append(
                {
                    "species_zh": (row.get("species_zh") or "").strip(),
                    "scientific_name": (row.get("scientific_name") or "").strip(),
                    "taxonomy_zh": (row.get("taxonomy_zh") or "").strip(),
                    "is_rare": (row.get("is_rare") or "").strip(),
                    "image_url": (row.get("image_url") or "").strip(),
                    "max_length_m": (row.get("max_length_m") or "").strip(),
                    "max_weight_kg": (row.get("max_weight_kg") or "").strip(),
                    "description_zh": (row.get("description_zh") or "").strip(),
                    "name_en": (row.get("name_en") or "").strip(),
                    "encyclopedia_category": (row.get("encyclopedia_category") or "").strip(),
                    "rarity_display": (row.get("rarity_display") or "").strip(),
                    "alias_zh": (row.get("alias_zh") or "").strip(),
                    "synonym": (row.get("synonym") or "").strip(),
                }
            )
    dedup: dict[str, dict[str, str]] = {}
    for r in rows:
        sci = " ".join(r["scientific_name"].split()).lower()
        if not sci:
            continue
        if sci not in dedup:
            dedup[sci] = r
    out = list(dedup.values())
    return out


def build_sql(rows: list[dict[str, str]], source_note: str) -> tuple[str, int]:
    values: list[str] = []
    alias_values: list[str] = []
    syn_values: list[str] = []

    for r in rows:
        zh = r["species_zh"]
        sci = r["scientific_name"] or zh
        if not zh or not sci:
            continue
        rare = parse_bool(r["is_rare"])
        img = r["image_url"] or PLACEHOLDER_IMAGE_URL
        try:
            max_m = float(r["max_length_m"] or "0")
        except ValueError:
            max_m = 0.0
        try:
            max_kg = float(r["max_weight_kg"] or "0")
        except ValueError:
            max_kg = 0.0
        desc = r["description_zh"] or "（暂无描述）"
        name_en = r["name_en"]
        enc = r["encyclopedia_category"]
        rd = norm_rarity_display(r["rarity_display"])
        alias = r["alias_zh"]

        name_en_sql = sql_str(name_en) if name_en else "null"
        enc_sql = sql_str(enc) if enc else "null"
        rd_sql = sql_str(rd) if rd is not None else "null"
        alias_sql = sql_str(alias) if alias else "null"

        values.append(
            "  ("
            + ", ".join(
                [
                    sql_str(zh),
                    sql_str(sci),
                    sql_str(r["taxonomy_zh"]),
                    "true" if rare else "false",
                    sql_str(img),
                    str(max_m),
                    str(max_kg),
                    sql_str(desc),
                    name_en_sql,
                    enc_sql,
                    rd_sql,
                    alias_sql,
                ]
            )
            + ")"
        )

        if alias:
            for a in alias.split(","):
                at = a.strip()
                if at:
                    alias_values.append(f"  ({sql_str(sci)}, {sql_str(at)})")
        synonym = r.get("synonym", "")
        if synonym:
            for s in synonym.split(","):
                st = s.strip()
                if st and st.lower() != sci.lower():
                    syn_values.append(f"  ({sql_str(st)}, {sql_str(sci)})")

    body = ",\n".join(values)
    alias_body = ",\n".join(alias_values) if alias_values else ""
    if alias_body:
        alias_insert_sql = (
            "insert into public.species_aliases (species_id, alias_zh)\n"
            "select sc.id, t.alias_zh\n"
            "from (values\n"
            + alias_body
            + "\n) t(scientific_name, alias_zh)\n"
            "join public.species_catalog sc on sc.scientific_name = t.scientific_name\n"
            "on conflict (alias_zh, species_id) do nothing;"
        )
    else:
        alias_insert_sql = "-- no aliases in CSV; skip alias insert"

    syn_body = ",\n".join(syn_values) if syn_values else ""
    if syn_body:
        synonym_insert_sql = (
            "insert into public.species_synonyms (synonym, canonical_scientific_name, source)\n"
            "values\n"
            + syn_body
            + "\n"
            "on conflict (lower(trim(synonym))) do update set\n"
            "  canonical_scientific_name = excluded.canonical_scientific_name,\n"
            "  source = 'taxonomic_db';"
        )
    else:
        synonym_insert_sql = "-- no synonyms in CSV; skip synonym insert"
    count = len(values)

    sql = f"""-- GENERATED — do not edit. From: {source_note}
-- Regenerate: python tool/export_species_catalog_supabase_sql.py
-- Canonical key: scientific_name

create temp table tmp_species_catalog_import (
  species_zh text not null,
  scientific_name text not null,
  taxonomy_zh text not null,
  is_rare boolean not null,
  image_url text not null,
  max_length_m numeric not null,
  max_weight_kg numeric not null,
  description_zh text not null,
  name_en text,
  encyclopedia_category text,
  rarity_display text,
  alias_zh text
) on commit drop;

insert into tmp_species_catalog_import (
  species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display, alias_zh
) values
{body};

-- Merge strategy to satisfy both unique constraints:
-- 1) update existing by scientific_name
update public.species_catalog sc
set
  species_zh = t.species_zh,
  taxonomy_zh = t.taxonomy_zh,
  is_rare = t.is_rare,
  image_url = t.image_url,
  max_length_m = t.max_length_m,
  max_weight_kg = t.max_weight_kg,
  description_zh = t.description_zh,
  name_en = t.name_en,
  encyclopedia_category = t.encyclopedia_category,
  rarity_display = t.rarity_display,
  alias_zh = t.alias_zh
from tmp_species_catalog_import t
where sc.scientific_name = t.scientific_name;

-- 2) update existing by species_zh when scientific_name did not match
update public.species_catalog sc
set
  scientific_name = t.scientific_name,
  taxonomy_zh = t.taxonomy_zh,
  is_rare = t.is_rare,
  image_url = t.image_url,
  max_length_m = t.max_length_m,
  max_weight_kg = t.max_weight_kg,
  description_zh = t.description_zh,
  name_en = t.name_en,
  encyclopedia_category = t.encyclopedia_category,
  rarity_display = t.rarity_display,
  alias_zh = t.alias_zh
from tmp_species_catalog_import t
where sc.species_zh = t.species_zh
  and not exists (
    select 1
    from public.species_catalog sc2
    where sc2.scientific_name = t.scientific_name
  );

-- 3) insert truly new rows (neither scientific_name nor species_zh exists)
insert into public.species_catalog (
  species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display, alias_zh
)
select
  t.species_zh, t.scientific_name, t.taxonomy_zh, t.is_rare, t.image_url,
  t.max_length_m, t.max_weight_kg, t.description_zh, t.name_en, t.encyclopedia_category, t.rarity_display, t.alias_zh
from tmp_species_catalog_import t
where not exists (
  select 1 from public.species_catalog sc where sc.scientific_name = t.scientific_name
)
and not exists (
  select 1 from public.species_catalog sc where sc.species_zh = t.species_zh
);

-- Remove old official rows no longer present in this import.
delete from public.species_catalog sc
where sc.source = 'official'
  and not exists (
    select 1
    from tmp_species_catalog_import t
    where t.species_zh = sc.species_zh
  );

-- Refresh normalized aliases for official rows.
delete from public.species_aliases a
using public.species_catalog sc
where a.species_id = sc.id
  and sc.source = 'official';

{alias_insert_sql}

-- Refresh scientific-name synonyms (if provided by CSV).
{synonym_insert_sql}
"""
    return sql, count


def main() -> None:
    p = argparse.ArgumentParser(description="Generate species_catalog import SQL from new CSV.")
    p.add_argument("--csv", type=Path, default=DEFAULT_TAXONOMY_CSV)
    p.add_argument("-o", "--output", type=Path, default=DEFAULT_OUT_SQL)
    p.add_argument("--stdout-only", action="store_true")
    args = p.parse_args()

    if not args.csv.is_file():
        raise SystemExit(f"missing csv: {args.csv}")

    rows = load_rows(args.csv)
    sql, n = build_sql(rows, str(args.csv.resolve()))

    if args.stdout_only:
        print(sql)
        return
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")
    print(f"Wrote {n} species -> {args.output}")


if __name__ == "__main__":
    main()
