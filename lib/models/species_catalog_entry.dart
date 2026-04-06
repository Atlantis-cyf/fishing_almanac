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

  /// Comma-separated Chinese aliases (e.g. '乌头,海鲋').
  final String? aliasZh;

  /// 'official' | 'user_contributed'
  final String source;

  /// 'approved' | 'pending' | 'rejected'
  final String status;

  final String? contributedBy;
  final String? contributedImageUrl;

  bool get isUserContributed => source == 'user_contributed';
  bool get isPending => status == 'pending';
  bool get isInfoIncomplete =>
      descriptionZh.isEmpty && maxLengthM <= 0 && maxWeightKg <= 0;

  factory SpeciesCatalogEntry.fromServerJson(Map<String, dynamic> json) {
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
    );
  }
}
