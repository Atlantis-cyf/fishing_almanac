# -*- coding: utf-8 -*-
"""Shared: dedupe species rows by scientific_name (keep smallest id = oldest)."""

from __future__ import annotations

FIELDNAMES = [
    "id",
    "species_zh",
    "scientific_name",
    "taxonomy_zh",
    "is_rare",
    "image_url",
    "max_length_m",
    "max_weight_kg",
    "description_zh",
    "name_en",
    "encyclopedia_category",
    "rarity_display",
    "created_at",
    "alias_zh",
]

CANON_SPECIES_ZH: dict[str, str] = {
    "日本竹?鱼": "日本竹䇲鱼",
}


def normalize_scientific_name(s: str) -> str:
    s = (s or "").strip()
    s = " ".join(s.split())
    return s.casefold()


def dedupe_taxonomy_row_dicts(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """For duplicate scientific_name, keep the row with minimum id. Empty scientific_name
    rows are keyed by species_zh only (no merge across different zh)."""
    best: dict[str, tuple[int, dict[str, str]]] = {}

    for row in rows:
        zh_raw = (row.get("species_zh") or "").strip()
        zh = CANON_SPECIES_ZH.get(zh_raw, zh_raw)
        row = {**row, "species_zh": zh}
        sci = (row.get("scientific_name") or "").strip()
        if sci:
            key = "sci:" + normalize_scientific_name(sci)
        else:
            key = "zh:" + zh

        try:
            sid = int((row.get("id") or "0").strip() or "0")
        except ValueError:
            sid = 0

        if key not in best:
            best[key] = (sid, row)
        else:
            old_sid, old_row = best[key]
            if sid < old_sid:
                best[key] = (sid, row)
            # else keep old (smaller id)

    out = [r for _, r in best.values()]
    out.sort(key=lambda r: int((r.get("id") or "0").strip() or "0"))
    return out
