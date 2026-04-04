#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate lib/data/species_catalog_data.g.dart from book CSV + image manifest.

Reads:
  D:\\fishingapp-cursor\\book\\species_library_taxonomy_image_updated.csv
  D:\\fishingapp-cursor\\book\\species_images\\species_images_manifest.csv

Copies images into: fishing_almanac/assets/species/
"""

from __future__ import annotations

import csv
import shutil
import sys
from io import StringIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_TOOL = Path(__file__).resolve().parent
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

from species_dedupe_core import CANON_SPECIES_ZH, FIELDNAMES, dedupe_taxonomy_row_dicts

BOOK = Path(r"D:\fishingapp-cursor\book")
TAXONOMY_CSV = BOOK / "species_library_taxonomy_image_updated.csv"
MANIFEST_CSV = BOOK / "species_images" / "species_images_manifest.csv"
ASSETS_DIR = ROOT / "assets" / "species"
OUT_DART = ROOT / "lib" / "data" / "species_catalog_data.g.dart"


def dart_str(s: str) -> str:
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    return "'" + s.replace("\\", r"\\").replace("'", r"\'").replace("\n", r"\n") + "'"


def parse_bool(raw: str) -> bool:
    t = (raw or "").strip().upper()
    return t in ("TRUE", "1", "YES", "Y", "T")


def main() -> None:
    manifest: dict[str, str] = {}
    with MANIFEST_CSV.open(encoding="utf-8-sig", newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            zh = (row.get("species_zh") or "").strip()
            lf = (row.get("local_file") or "").strip()
            if zh and lf:
                manifest[zh] = lf

    rows: list[dict[str, str]] = []
    raw = TAXONOMY_CSV.read_bytes()
    text = None
    for enc in ("utf-8-sig", "gbk", "utf-8"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        text = raw.decode("utf-8", errors="replace")

    f = StringIO(text)
    reader = csv.reader(f)
    header = next(reader, None)
    if not header:
        raise SystemExit("empty taxonomy csv")
    for raw in reader:
        if not raw or all(not (c or "").strip() for c in raw):
            continue
        while len(raw) < len(FIELDNAMES):
            raw.append("")
        row = dict(zip(FIELDNAMES, raw[: len(FIELDNAMES)]))
        rows.append(row)

    before_n = len(rows)
    rows = dedupe_taxonomy_row_dicts(rows)
    if len(rows) < before_n:
        print(f"Deduped by scientific_name: {before_n} -> {len(rows)} rows (kept smallest id)")

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    src_dir = BOOK / "species_images"
    copied = 0
    for zh, lf in manifest.items():
        src = src_dir / lf
        dst = ASSETS_DIR / lf
        if not src.is_file():
            print(f"WARN missing image file: {src}")
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
        if rarity_disp.upper() in ("FALSE", "TRUE", ""):
            rarity_disp = ""
        if rarity_disp.upper() in ("FALSE", "TRUE", "NONE", ""):
            rarity_disp = ""
        try:
            max_m = float((row.get("max_length_m") or "0").strip() or "0")
        except ValueError:
            max_m = 0.0
        try:
            max_kg = float((row.get("max_weight_kg") or "0").strip() or "0")
        except ValueError:
            max_kg = 0.0

        lf = manifest.get(zh)
        if not lf:
            print(f"WARN no manifest image for: {zh}")
            lf = "鲯鳅.jpg"
        asset_path = f"assets/species/{lf}"

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
        lines.append(f"    imageUrl: {dart_str(asset_path)},")
        lines.append(f"    maxLengthM: {max_m},")
        lines.append(f"    maxWeightKg: {max_kg},")
        lines.append(f"    descriptionZh: {dart_str(desc)},")
        lines.append(f"    nameEn: {opt_field(name_en)},")
        lines.append(f"    encyclopediaCategory: {opt_field(enc_cat)},")
        lines.append(f"    rarityDisplay: {opt_field(rarity_disp)},")
        lines.append("  ),")

    # Placeholders for catches FK / free-text (same asset as a known fish for offline hero).
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
    lines.append("  ),")

    lines.append("];")
    lines.append("")

    OUT_DART.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT_DART}")


if __name__ == '__main__':
    main()
