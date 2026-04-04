#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Remove duplicate species in book CSV by scientific_name: keep smallest id (oldest), drop newer.

Rewrites:
  D:\\fishingapp-cursor\\book\\species_library_taxonomy_image_updated.csv
Backs up to:
  species_library_taxonomy_image_updated.csv.bak

Also trims species_images_manifest.csv to species_zh still present (backup .bak).
"""

from __future__ import annotations

import csv
import shutil
import sys
from io import StringIO
from pathlib import Path

_TOOL = Path(__file__).resolve().parent
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

from species_dedupe_core import FIELDNAMES, dedupe_taxonomy_row_dicts

BOOK = Path(r"D:\fishingapp-cursor\book")
TAXONOMY_CSV = BOOK / "species_library_taxonomy_image_updated.csv"
MANIFEST_CSV = BOOK / "species_images" / "species_images_manifest.csv"


def read_taxonomy_text() -> str:
    raw = TAXONOMY_CSV.read_bytes()
    for enc in ("utf-8-sig", "gbk", "utf-8"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def main() -> None:
    text = read_taxonomy_text()
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

    before = len(rows)
    rows = dedupe_taxonomy_row_dicts(rows)
    after = len(rows)
    removed = before - after
    if removed:
        print(f"scientific_name duplicates: removed {removed} row(s) ({before} -> {after}), kept smallest id.")
    else:
        print("No duplicate scientific_name; taxonomy file unchanged.")

    kept_zh = {(r.get("species_zh") or "").strip() for r in rows}

    if removed:
        shutil.copy2(TAXONOMY_CSV, TAXONOMY_CSV.with_suffix(".csv.bak"))
        with TAXONOMY_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=FIELDNAMES, extrasaction="ignore")
            w.writeheader()
            for row in rows:
                w.writerow(row)
        print(f"Wrote {TAXONOMY_CSV}")

    # Sync manifest: drop rows for species_zh no longer in taxonomy
    if not MANIFEST_CSV.is_file():
        return
    with MANIFEST_CSV.open(encoding="utf-8-sig", newline="") as f:
        mrows = list(csv.DictReader(f))
    if not mrows:
        return
    fields = list(mrows[0].keys())
    filtered = [r for r in mrows if (r.get("species_zh") or "").strip() in kept_zh]
    mf_removed = len(mrows) - len(filtered)
    if mf_removed:
        shutil.copy2(MANIFEST_CSV, MANIFEST_CSV.with_suffix(".csv.bak"))
        with MANIFEST_CSV.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            w.writerows(filtered)
        print(f"Manifest: removed {mf_removed} orphan row(s); backup .bak")


if __name__ == "__main__":
    main()
