/// 与 `supabase/migrations/0003_species_catalog.sql` 表 `species_catalog` 字段对齐。
class SpeciesCatalogEntry {
  const SpeciesCatalogEntry({
    required this.id,
    required this.speciesZh,
    required this.scientificName,
    required this.taxonomyZh,
    required this.isRare,
    required this.imageUrl,
    required this.maxLengthM,
    required this.maxWeightKg,
    required this.descriptionZh,
    this.nameEn,
    this.encyclopediaCategory,
    this.rarityDisplay,
    this.aliasZh,
    this.source = 'official',
    this.status = 'approved',
    this.contributedBy,
    this.contributedImageUrl,
    this.aliases = const [],
    this.synonyms = const [],
  });

  final int id;
  final String speciesZh;
  final String scientificName;
  final String taxonomyZh;
  final bool isRare;
  final String imageUrl;
  final double maxLengthM;
  final double maxWeightKg;
  final String descriptionZh;
  final String? nameEn;
  final String? encyclopediaCategory;
  final String? rarityDisplay;

  /// Comma-separated Chinese aliases (legacy, e.g. '乌头,海鲋').
  final String? aliasZh;

  /// 'official' | 'user_contributed'
  final String source;

  /// 'approved' | 'pending' | 'rejected'
  final String status;

  final String? contributedBy;
  final String? contributedImageUrl;

  /// Normalized alias list from species_aliases table.
  final List<SpeciesAlias> aliases;

  /// Scientific name synonyms from species_synonyms table.
  final List<SpeciesSynonym> synonyms;

  bool get isUserContributed => source == 'user_contributed';
  bool get isPending => status == 'pending';
  bool get isInfoIncomplete =>
      descriptionZh.isEmpty && maxLengthM <= 0 && maxWeightKg <= 0;

  /// 与首页「稀有记录」、百科珍惜筛选一致：`is_rare` 或展示文案含稀有/保护。
  bool get countsAsRareSpecies {
    if (isRare) return true;
    final d = rarityDisplay ?? '';
    if (d.contains('稀有') || d.contains('保护')) return true;
    return false;
  }

  /// All Chinese alias strings (from both legacy aliasZh and the aliases list).
  List<String> get allAliasZh {
    final result = <String>{};
    if (aliasZh != null && aliasZh!.isNotEmpty) {
      for (final a in aliasZh!.split(',')) {
        final t = a.trim();
        if (t.isNotEmpty) result.add(t);
      }
    }
    for (final a in aliases) {
      final t = a.aliasZh.trim();
      if (t.isNotEmpty) result.add(t);
    }
    return result.toList();
  }

  /// All scientific name synonyms (strings only).
  List<String> get allSynonyms => synonyms.map((s) => s.synonym).toList();

  factory SpeciesCatalogEntry.fromServerJson(Map<String, dynamic> json) {
    final aliasesList = json['aliases'];
    final synonymsList = json['synonyms'];

    return SpeciesCatalogEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      speciesZh: (json['species_zh'] as String?) ?? '',
      scientificName: (json['scientific_name'] as String?) ?? '',
      taxonomyZh: (json['taxonomy_zh'] as String?) ?? '',
      isRare: json['is_rare'] == true,
      imageUrl: (json['image_url'] as String?) ?? '',
      maxLengthM: (json['max_length_m'] as num?)?.toDouble() ?? 0,
      maxWeightKg: (json['max_weight_kg'] as num?)?.toDouble() ?? 0,
      descriptionZh: (json['description_zh'] as String?) ?? '',
      nameEn: json['name_en'] as String?,
      encyclopediaCategory: json['encyclopedia_category'] as String?,
      rarityDisplay: json['rarity_display'] as String?,
      aliasZh: json['alias_zh'] as String?,
      source: (json['source'] as String?) ?? 'official',
      status: (json['status'] as String?) ?? 'approved',
      contributedBy: json['contributed_by'] as String?,
      contributedImageUrl: json['contributed_image_url'] as String?,
      aliases: aliasesList is List
          ? aliasesList
              .whereType<Map<String, dynamic>>()
              .map(SpeciesAlias.fromJson)
              .toList()
          : const [],
      synonyms: synonymsList is List
          ? synonymsList
              .whereType<Map<String, dynamic>>()
              .map(SpeciesSynonym.fromJson)
              .toList()
          : const [],
    );
  }
}

class SpeciesAlias {
  const SpeciesAlias({
    required this.id,
    required this.aliasZh,
    required this.speciesId,
    this.region,
  });

  final int id;
  final String aliasZh;
  final int speciesId;
  final String? region;

  factory SpeciesAlias.fromJson(Map<String, dynamic> json) {
    return SpeciesAlias(
      id: (json['id'] as num?)?.toInt() ?? 0,
      aliasZh: (json['alias_zh'] as String?) ?? '',
      speciesId: (json['species_id'] as num?)?.toInt() ?? 0,
      region: json['region'] as String?,
    );
  }
}

class SpeciesSynonym {
  const SpeciesSynonym({
    required this.id,
    required this.synonym,
    required this.canonicalScientificName,
    this.source = 'manual',
  });

  final int id;
  final String synonym;
  final String canonicalScientificName;
  final String source;

  factory SpeciesSynonym.fromJson(Map<String, dynamic> json) {
    return SpeciesSynonym(
      id: (json['id'] as num?)?.toInt() ?? 0,
      synonym: (json['synonym'] as String?) ?? '',
      canonicalScientificName:
          (json['canonical_scientific_name'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'manual',
    );
  }
}
