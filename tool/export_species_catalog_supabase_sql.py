#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 book 物种 taxonomy CSV 生成 `species_catalog` 的 upsert SQL（云端鱼获外键用）。

推荐流程（不维护仓库里的大段手写 SQL）：
  1. 编辑 book 目录下 taxonomy CSV
  2. 运行本脚本生成 SQL（默认写入 supabase/seed/，或用 --stdout-only 管道）
  3. 在 Supabase SQL Editor 执行生成结果，或 `psql` / `supabase db execute` 等

前置：已在线上执行 migrations 0001–0004。
插入不写 `id`；`ON CONFLICT (species_zh) DO UPDATE`，可重复执行。
"""

from __future__ import annotations

import argparse
import csv
import sys
from io import StringIO
from pathlib import Path

_TOOL = Path(__file__).resolve().parent
_ROOT = Path(__file__).resolve().parents[1]
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

from species_dedupe_core import FIELDNAMES, dedupe_taxonomy_row_dicts

DEFAULT_BOOK = Path(r"D:\fishingapp-cursor\book")
DEFAULT_TAXONOMY_CSV = DEFAULT_BOOK / "species_library_taxonomy_image_updated.csv"
DEFAULT_OUT_SQL = _ROOT / "supabase" / "seed" / "species_catalog_from_book_upsert.sql"

# NOT NULL image_url when CSV cell is empty（App 图鉴仍用 assets/species/）。
PLACEHOLDER_IMAGE_URL = (
    "https://lh3.googleusercontent.com/aida-public/"
    "AB6AXuDUUhNpUHCjj1aSmC8lmt-mr5XKR0iEo-FDabChHlRaF7mSO1u2qQqZ-3L3aIgX5_5L84LolksWSXcXFw3p0Q64CWLUD4pSuFyYs4Eosjt3bAkpHMjOTxWPPi8q3TG5K-zNP8LtuIBOaY6gXBqqbe_UwpO3wbnEIS0EkMXIA8-T7HoNCk4mMeiHRo6Yb8UAX_qlDDaYuP6hLM9Da51N6UPg96KMMefSlEj5xKzDlIsI74KtD9RK_eA281Ql9xdvqZ1DRyUbNTHO7A"
)


def read_taxonomy_text(csv_path: Path) -> str:
    raw = csv_path.read_bytes()
    for enc in ("utf-8-sig", "gbk", "utf-8"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def parse_bool(raw: str) -> bool:
    t = (raw or "").strip().upper()
    return t in ("TRUE", "1", "YES", "Y", "T")


def sql_str(s: str) -> str:
    return "'" + (s or "").replace("\\", "\\\\").replace("'", "''") + "'"


def norm_rarity_display(raw: str) -> str | None:
    t = (raw or "").strip()
    if not t:
        return None
    u = t.upper()
    if u in ("FALSE", "TRUE", "NONE", ""):
        return None
    return t


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    text = read_taxonomy_text(csv_path)
    reader = csv.reader(StringIO(text))
    header = next(reader, None)
    if not header:
        raise SystemExit("empty taxonomy csv")
    rows: list[dict[str, str]] = []
    for raw in reader:
        if not raw or all(not (c or "").strip() for c in raw):
            continue
        while len(raw) < len(FIELDNAMES):
            raw.append("")
        rows.append(dict(zip(FIELDNAMES, raw[: len(FIELDNAMES)])))
    return dedupe_taxonomy_row_dicts(rows)


def build_sql(rows: list[dict[str, str]], source_note: str) -> tuple[str, int]:
    value_lines: list[str] = []
    for row in rows:
        zh = (row.get("species_zh") or "").strip()
        if not zh:
            continue
        sci = (row.get("scientific_name") or "").strip() or zh
        tax = (row.get("taxonomy_zh") or "").strip()
        rare = parse_bool(row.get("is_rare") or "")
        img = (row.get("image_url") or "").strip() or PLACEHOLDER_IMAGE_URL
        try:
            max_m = float((row.get("max_length_m") or "0").strip() or "0")
        except ValueError:
            max_m = 0.0
        try:
            max_kg = float((row.get("max_weight_kg") or "0").strip() or "0")
        except ValueError:
            max_kg = 0.0
        desc = (row.get("description_zh") or "").strip() or "（暂无描述）"
        name_en = (row.get("name_en") or "").strip()
        enc_cat = (row.get("encyclopedia_category") or "").strip()
        rdis = norm_rarity_display(row.get("rarity_display") or "")
        alias_zh = (row.get("alias_zh") or "").strip()

        name_en_sql = sql_str(name_en) if name_en else "null"
        enc_sql = sql_str(enc_cat) if enc_cat else "null"
        rare_sql = sql_str(rdis) if rdis is not None else "null"
        alias_sql = sql_str(alias_zh) if alias_zh else "null"

        parts = [
            sql_str(zh),
            sql_str(sci),
            sql_str(tax),
            "true" if rare else "false",
            sql_str(img),
            str(max_m),
            str(max_kg),
            sql_str(desc),
            name_en_sql,
            enc_sql,
            rare_sql,
            alias_sql,
        ]

        value_lines.append("  (" + ", ".join(parts) + ")")

    body = ",\n".join(value_lines)
    count = len(value_lines)

    sql = f"""-- GENERATED — do not edit. From: {source_note}
-- Regenerate: python tool/export_species_catalog_supabase_sql.py
-- Deduped by scientific_name (same as generate_species_catalog).
--
-- Upsert for catches.species_zh FK. Safe to re-run (ON CONFLICT).
-- image_url: CSV empty → placeholder HTTPS; app encyclopedia uses assets/species/.

insert into public.species_catalog (
  species_zh, scientific_name, taxonomy_zh, is_rare, image_url,
  max_length_m, max_weight_kg, description_zh, name_en, encyclopedia_category, rarity_display,
  alias_zh
) values
{body}
on conflict (species_zh) do update set
  scientific_name = excluded.scientific_name,
  taxonomy_zh = excluded.taxonomy_zh,
  is_rare = excluded.is_rare,
  image_url = excluded.image_url,
  max_length_m = excluded.max_length_m,
  max_weight_kg = excluded.max_weight_kg,
  description_zh = excluded.description_zh,
  name_en = excluded.name_en,
  encyclopedia_category = excluded.encyclopedia_category,
  rarity_display = excluded.rarity_display,
  alias_zh = excluded.alias_zh;

select setval(
  pg_get_serial_sequence('public.species_catalog', 'id'),
  (select coalesce(max(id), 1) from public.species_catalog)
);
"""
    return sql, count


def main() -> None:
    p = argparse.ArgumentParser(
        description="Generate species_catalog upsert SQL from taxonomy CSV (for Supabase / psql)."
    )
    p.add_argument(
        "--csv",
        type=Path,
        default=DEFAULT_TAXONOMY_CSV,
        help=f"taxonomy CSV path (default: {DEFAULT_TAXONOMY_CSV})",
    )
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        default=DEFAULT_OUT_SQL,
        help=f"write SQL to this file (default: {DEFAULT_OUT_SQL})",
    )
    p.add_argument(
        "--stdout-only",
        action="store_true",
        help="print SQL to stdout only (UTF-8), do not write a file",
    )
    args = p.parse_args()

    csv_path: Path = args.csv
    if not csv_path.is_file():
        raise SystemExit(f"missing taxonomy csv: {csv_path}")

    rows = load_rows(csv_path)
    sql, n = build_sql(rows, str(csv_path.resolve()))

    if args.stdout_only:
        # Windows 控制台常为 GBK；写 buffer 保证 UTF-8，便于重定向到文件或 psql
        payload = sql if sql.endswith("\n") else sql + "\n"
        sys.stdout.buffer.write(payload.encode("utf-8"))
        print(f"# {n} species rows", file=sys.stderr)
        return

    out: Path = args.output
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(sql, encoding="utf-8")
    print(f"Wrote {n} species -> {out}")


if __name__ == "__main__":
    main()
