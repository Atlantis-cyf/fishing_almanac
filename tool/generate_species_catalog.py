#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""Generate lib/data/species_catalog_data.g.dart from CSV + local image folder.

Default reads:
  D:\fishingapp-cursor\book\2.0豆包\抓取图片\species_catalog_wikipedia_images_filled.csv
  D:\fishingapp-cursor\book\2.0豆包\抓取图片\species_images_all\ (optional local images)

Copies local images into: fishing_almanac/assets/species/
If local image is missing, keeps CSV image_url as network fallback.
"""

from __future__ import annotations

import argparse
import csv
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_TOOL = Path(__file__).resolve().parent
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

from species_dedupe_core import CANON_SPECIES_ZH, dedupe_taxonomy_row_dicts

BOOK = Path(r"D:\fishingapp-cursor\book\2.0豆包\抓取图片")
DEFAULT_TAXONOMY_CSV = BOOK / "species_catalog_wikipedia_images_filled.csv"
DEFAULT_IMAGES_DIR = BOOK / "species_images_all"
ASSETS_DIR = ROOT / "assets" / "species"
OUT_DART = ROOT / "lib" / "data" / "species_catalog_data.g.dart"


def dart_str(s: str) -> str:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    return "'" + s.replace("\\", r"\\").replace("'", r"\'").replace("\n", r"\n") + "'"


def parse_bool(raw: str) -> bool:
    t = (raw or "").strip().upper()
    return t in ("TRUE", "1", "YES", "Y", "T")


def _pick(row: dict[str, str], *keys: str) -> str:
    for k in keys:
        v = row.get(k)
        if v is not None:
            return str(v)
    return ""


def _norm_rows(csv_path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with csv_path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row:
                continue
            if all(not str(v or "").strip() for v in row.values()):
                continue
            rows.append(
                {
                    "id": _pick(row, "id", "species_id").strip(),
                    "species_zh": _pick(row, "species_zh").strip(),
                    "scientific_name": _pick(row, "scientific_name").strip(),
                    "taxonomy_zh": _pick(row, "taxonomy_zh").strip(),
                    "is_rare": _pick(row, "is_rare").strip(),
                    "image_url": _pick(row, "image_url").strip(),
                    "max_length_m": _pick(row, "max_length_m").strip(),
                    "max_weight_kg": _pick(row, "max_weight_kg").strip(),
                    "description_zh": _pick(row, "description_zh").strip(),
                    "name_en": _pick(row, "name_en").strip(),
                    "encyclopedia_category": _pick(row, "encyclopedia_category").strip(),
                    "rarity_display": _pick(row, "rarity_display").strip(),
                    "created_at": _pick(row, "created_at").strip(),
                    "alias_zh": _pick(row, "alias_zh").strip(),
                }
            )
    return rows


def _build_local_image_map(images_dir: Path) -> dict[str, str]:
    by_zh: dict[str, str] = {}
    if not images_dir.is_dir():
        return by_zh
    for p in images_dir.iterdir():
        if not p.is_file():
            continue
        ext = p.suffix.lower()
        if ext not in (".jpg", ".jpeg", ".png", ".webp", ".gif"):
            continue
        by_zh[p.stem] = p.name
    return by_zh


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate species catalog Dart data from CSV + local images.")
    ap.add_argument("--csv", type=Path, default=DEFAULT_TAXONOMY_CSV)
    ap.add_argument("--images-dir", type=Path, default=DEFAULT_IMAGES_DIR)
    args = ap.parse_args()

    csv_path: Path = args.csv
    images_dir: Path = args.images_dir
    if not csv_path.is_file():
        raise SystemExit(f"missing taxonomy csv: {csv_path}")

    rows = _norm_rows(csv_path)
    before_n = len(rows)
    rows = dedupe_taxonomy_row_dicts(rows)
    if len(rows) < before_n:
        print(f"Deduped by scientific_name: {before_n} -> {len(rows)} rows (kept smallest id)")

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    local_images = _build_local_image_map(images_dir)
    copied = 0
    for _, lf in local_images.items():
        src = images_dir / lf
        dst = ASSETS_DIR / lf
        if not src.is_file():
            continue
        shutil.copy2(src, dst)
        copied += 1
    print(f"Copied {copied} image(s) to {ASSETS_DIR}")

    lines: list[str] = []
    lines.append("// GENERATED FILE — do not edit by hand.")
    lines.append("// Run: python tool/generate_species_catalog.py")
    lines.append("")
    lines.append("part of 'species_catalog.dart';")
    lines.append("")
    lines.append("const List<SpeciesCatalogEntry> kSpeciesCatalogAll = [")

    for row in rows:
        zh = (row.get("species_zh") or "").strip()
        zh = CANON_SPECIES_ZH.get(zh, zh)
        if not zh:
            continue
        sid = int((row.get("id") or "0").strip() or "0")
        sci = (row.get("scientific_name") or "").strip()
        tax = (row.get("taxonomy_zh") or "").strip()
        rare = parse_bool(row.get("is_rare") or "")
        desc = (row.get("description_zh") or "").strip()
        name_en = (row.get("name_en") or "").strip()
        enc_cat = (row.get("encyclopedia_category") or "").strip()
        rarity_disp = (row.get("rarity_display") or "").strip()
        if rarity_disp.upper() in ("FALSE", "TRUE", "NONE", ""):
            rarity_disp = ""
        alias_zh = (row.get("alias_zh") or "").strip()
        try:
            max_m = float((row.get("max_length_m") or "0").strip() or "0")
        except ValueError:
            max_m = 0.0
        try:
            max_kg = float((row.get("max_weight_kg") or "0").strip() or "0")
        except ValueError:
            max_kg = 0.0

        lf = local_images.get(zh)
        if lf:
            image_ref = f"assets/species/{lf}"
        else:
            image_ref = (row.get("image_url") or "").strip() or "assets/species/鲯鳅.jpg"
            print(f"WARN no local image for: {zh}")

        def opt_field(s: str | None) -> str:
            if not s:
                return "null"
            return dart_str(s)

        lines.append("  SpeciesCatalogEntry(")
        lines.append(f"    id: {sid},")
        lines.append(f"    speciesZh: {dart_str(zh)},")
        lines.append(f"    scientificName: {dart_str(sci)},")
        lines.append(f"    taxonomyZh: {dart_str(tax)},")
        lines.append(f"    isRare: {str(rare).lower()},")
        lines.append(f"    imageUrl: {dart_str(image_ref)},")
        lines.append(f"    maxLengthM: {max_m},")
        lines.append(f"    maxWeightKg: {max_kg},")
        lines.append(f"    descriptionZh: {dart_str(desc)},")
        lines.append(f"    nameEn: {opt_field(name_en)},")
        lines.append(f"    encyclopediaCategory: {opt_field(enc_cat)},")
        lines.append(f"    rarityDisplay: {opt_field(rarity_disp)},")
        lines.append(f"    aliasZh: {opt_field(alias_zh)},")
        lines.append("  ),")

    lines.append("  SpeciesCatalogEntry(")
    lines.append("    id: 100,")
    lines.append("    speciesZh: '未确定',")
    lines.append("    scientificName: 'Indeterminate',")
    lines.append("    taxonomyZh: '未定种 · 待鉴定',")
    lines.append("    isRare: false,")
    lines.append("    imageUrl: 'assets/species/鲯鳅.jpg',")
    lines.append("    maxLengthM: 0,")
    lines.append("    maxWeightKg: 0,")
    lines.append("    descriptionZh: '用户尚未确认具体鱼种，可在后续编辑中更正。',")
    lines.append("    nameEn: 'Unknown',")
    lines.append("    encyclopediaCategory: null,")
    lines.append("    rarityDisplay: null,")
    lines.append("    aliasZh: null,")
    lines.append("  ),")
    lines.append("  SpeciesCatalogEntry(")
    lines.append("    id: 101,")
    lines.append("    speciesZh: '未命名鱼种',")
    lines.append("    scientificName: 'Unnamed species',")
    lines.append("    taxonomyZh: '未定种 · 待命名',")
    lines.append("    isRare: false,")
    lines.append("    imageUrl: 'assets/species/鲯鳅.jpg',")
    lines.append("    maxLengthM: 0,")
    lines.append("    maxWeightKg: 0,")
    lines.append("    descriptionZh: '尚未在图鉴中单独命名的鱼种占位条目。',")
    lines.append("    nameEn: 'Unnamed',")
    lines.append("    encyclopediaCategory: null,")
    lines.append("    rarityDisplay: null,")
    lines.append("    aliasZh: null,")
    lines.append("  ),")
    lines.append("];")
    lines.append("")

    OUT_DART.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT_DART}")


if __name__ == "__main__":
    main()
