import 'package:fishing_almanac/models/species_catalog_entry.dart';

part 'species_catalog_data.g.dart';

/// 物种库条目由 `tool/generate_species_catalog.py` 从 book 目录 CSV + 本地图生成。
/// 图片路径形如 `assets/species/<中文名>.jpg`，见 `pubspec.yaml`。
abstract final class SpeciesCatalog {
  static const List<SpeciesCatalogEntry> all = kSpeciesCatalogAll;
  static const String otherScientificName = 'Other';
  static const String otherSpeciesZh = '其它';

  static const SpeciesCatalogEntry otherEntry = SpeciesCatalogEntry(
    id: -1,
    speciesZh: otherSpeciesZh,
    scientificName: otherScientificName,
    taxonomyZh: '未识别分类',
    isRare: false,
    imageUrl: '',
    maxLengthM: 0,
    maxWeightKg: 0,
    descriptionZh: '该目录用于收录 AI 判断为非鱼或无法有效识别、但用户仍选择保留的记录。',
  );

  /// 与鱼获、外键对齐：空白折叠 + 大小写不敏感。
  static String normalizeScientificNameKey(String raw) {
    return raw.trim().split(RegExp(r'\s+')).join(' ').toLowerCase();
  }

  static SpeciesCatalogEntry? tryByScientificName(String raw) {
    final k = normalizeScientificNameKey(raw);
    if (k.isEmpty) return null;
    if (k == normalizeScientificNameKey(otherScientificName)) return otherEntry;
    for (final e in all) {
      if (normalizeScientificNameKey(e.scientificName) == k) return e;
    }
    return null;
  }

  static SpeciesCatalogEntry? tryBySpeciesZh(String speciesFilterZh) {
    final k = speciesFilterZh.trim();
    if (k.isEmpty) return null;
    if (k == otherSpeciesZh) return otherEntry;
    for (final e in all) {
      if (e.speciesZh == k) return e;
    }
    return null;
  }

  /// 编辑页物种搜索：中文名子串 + 拉丁/英文名子串（不区分大小写）+ 分类文案，按相关度排序。
  static List<SpeciesCatalogEntry> searchSpeciesForEdit(
    String rawQuery, {
    int limit = 16,
    List<SpeciesCatalogEntry>? entries,
  }) {
    final q = rawQuery.trim();
    if (q.isEmpty) return const [];
    final qLower = q.toLowerCase();
    final limitClamped = limit.clamp(1, 64);

    final hits = <({SpeciesCatalogEntry e, int score})>[];
    for (final e in (entries ?? all)) {
      final zh = e.speciesZh.trim();
      if (zh.isEmpty) continue;

      var score = 0;
      if (zh.contains(q)) {
        score += zh.startsWith(q) ? 120 : 70;
        final idx = zh.indexOf(q);
        if (idx >= 0) score += (24 - idx).clamp(0, 24);
      }

      final sciLower = e.scientificName.toLowerCase();
      if (sciLower.contains(qLower)) {
        score += sciLower.startsWith(qLower) ? 55 : 40;
      }

      final en = (e.nameEn ?? '').trim().toLowerCase();
      if (en.isNotEmpty && en.contains(qLower)) {
        score += en.startsWith(qLower) ? 40 : 28;
      }

      // Match against all aliases (legacy comma-separated + normalized list)
      for (final at in e.allAliasZh) {
        if (at.contains(q)) {
          score += at.startsWith(q) ? 90 : 65;
          break;
        }
      }

      // Match against scientific name synonyms
      for (final syn in e.allSynonyms) {
        final synLower = syn.toLowerCase();
        if (synLower.contains(qLower)) {
          score += synLower.startsWith(qLower) ? 50 : 35;
          break;
        }
      }

      if (e.taxonomyZh.contains(q)) {
        score += 12;
      }

      if (score > 0) hits.add((e: e, score: score));
    }

    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.e.speciesZh.compareTo(b.e.speciesZh);
    });

    return hits.take(limitClamped).map((h) => h.e).toList();
  }

  /// 未知鱼种：用拉丁占位；展示仍可用中文入参转成学名键。
  static SpeciesCatalogEntry fallbackForScientificName(String scientificNameRaw) {
    final s = scientificNameRaw.trim();
    return SpeciesCatalogEntry(
      id: 0,
      speciesZh: s.isEmpty ? '未知物种' : s,
      scientificName: s.isEmpty ? 'Unknown' : s,
      taxonomyZh: '待补充',
      isRare: false,
      imageUrl: 'assets/species/鲯鳅.jpg',
      maxLengthM: 2.5,
      maxWeightKg: 250,
      descriptionZh: '$s 是图鉴中的代表性目标鱼种之一。',
    );
  }

  /// 未知中文名：占位条目（学名等于入参，可能不在库中）。
  static SpeciesCatalogEntry fallbackForZh(String speciesFilterZh) {
    final zh = speciesFilterZh.trim();
    return SpeciesCatalogEntry(
      id: 0,
      speciesZh: zh.isEmpty ? '未知物种' : zh,
      scientificName: zh.isEmpty ? 'Unknown' : zh,
      taxonomyZh: '待补充',
      isRare: false,
      imageUrl: 'assets/species/鲯鳅.jpg',
      maxLengthM: 2.5,
      maxWeightKg: 250,
      descriptionZh: '$zh 是图鉴中的代表性目标鱼种之一。',
    );
  }

  static SpeciesCatalogEntry byScientificName(String scientificNameRaw) {
    return tryByScientificName(scientificNameRaw) ?? fallbackForScientificName(scientificNameRaw);
  }

  static SpeciesCatalogEntry bySpeciesZh(String speciesFilterZh) {
    return tryBySpeciesZh(speciesFilterZh) ?? fallbackForZh(speciesFilterZh);
  }

  /// 用户输入（中文名或拉丁名）→ 存库用学名；占位鱼种固定映射。
  static String resolveScientificNameFromUserInput(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t == otherSpeciesZh) return otherScientificName;
    if (t == '未确定') return 'Indeterminate';
    if (t == '未命名鱼种') return 'Unnamed species';
    final byZh = tryBySpeciesZh(t);
    if (byZh != null) return byZh.scientificName;
    final bySci = tryByScientificName(t);
    if (bySci != null) return bySci.scientificName;
    return t;
  }

  /// 编辑页展示用中文名（控制器文本）。
  static String displayZhForScientific(String scientificName) {
    final s = scientificName.trim();
    if (s.isEmpty) return '';
    if (normalizeScientificNameKey(s) == normalizeScientificNameKey(otherScientificName)) {
      return otherSpeciesZh;
    }
    return tryByScientificName(s)?.speciesZh ?? s;
  }
}
